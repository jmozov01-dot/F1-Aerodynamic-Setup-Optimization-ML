function resultado = entrenar_modelo(pathToApp, temporada)
    rng(1);
    resultado = struct();
    resultado.success = false;
    
    % Carpetas según temporada
    if nargin < 2, temporada = '2025'; end
    if strcmp(temporada, '2026')
        folderDatos = 'datos_2026'; folderModelos = 'modelos_2026';
    else
        folderDatos = 'datos'; folderModelos = 'modelos';
    end
    datosPath = fullfile(pathToApp, folderDatos);
    
%% PASO 4: Modelo ML
% Cargar datos
files = dir(fullfile(datosPath, 'circuit_*.mat'));
circuitos = {};
datos_todos = [];

% Calcular pesos automáticos
vueltas_por_circuito = containers.Map();
for i = 1:length(files)
    nombre = strrep(strrep(files(i).name, 'circuit_',''), '.mat','');
    laps_file = fullfile(datosPath, sprintf('laps_%s.mat', nombre));    
    if exist(laps_file, 'file')
        temp_laps = load(laps_file).laps.lap_data;
        vueltas_por_circuito(nombre) = sum(temp_laps(:,2) > 0);
    end
end
max_vueltas = max(cell2mat(values(vueltas_por_circuito)));

for i = 1:length(files)
    nombre = strrep(strrep(files(i).name, 'circuit_',''), '.mat','');
    
    if ~exist(fullfile(datosPath, sprintf('laps_%s.mat', nombre)), 'file') || ~exist(fullfile(datosPath, sprintf('telemetry_%s.mat', nombre)), 'file')
        continue;
    end
    
    circuitos{end+1} = nombre;
    
    circuit_data = load(fullfile(datosPath, sprintf('circuit_%s.mat', nombre))).circuit_data;
    laps = load(fullfile(datosPath, sprintf('laps_%s.mat', nombre))).laps.lap_data;
    telemetry = load(fullfile(datosPath, sprintf('telemetry_%s.mat', nombre))).telemetry;
    
    curv = abs(circuit_data.curvature);
    n_pts = length(curv);
    r_rectas = sum(curv < 0.002) / n_pts;
    r_rapidas = sum(curv >= 0.002 & curv < 0.006) / n_pts;
    r_lentas = sum(curv >= 0.006) / n_pts;
    
    tiempos = laps(laps(:,2)>0, 2);
    mu_local = mean(tiempos);
    sigma_local = std(tiempos);
    if sigma_local == 0, sigma_local = 1; end
    
    for k = 1:size(laps, 1)
        fw = laps(k,4);
        rw = laps(k,5);
        tiempo = laps(k,2);
        lap_id = laps(k,1);
        
        if tiempo <= 0, continue; end
        
        idx = find(telemetry.lap_metrics.lap_id == lap_id, 1);
        if isempty(idx), continue; end
        
        tm = telemetry.lap_metrics;
        telem = [tm.v_max(idx), tm.glat_media(idx), tm.glong_acel(idx), tm.glong_freno(idx), tm.t_acelerador(idx), tm.t_freno(idx), tm.steering_std(idx)];
        z_score = (tiempo - mu_local) / sigma_local;
        
        w = max_vueltas / vueltas_por_circuito(nombre); % Peso por circuito
        
        fila = [fw, rw, z_score, r_rectas, r_rapidas, r_lentas, telem, mu_local, sigma_local, w];
        datos_todos = [datos_todos; fila];
    end
end

%% Modelos auxiliares
X_aux = [datos_todos(:, 1:2), datos_todos(:, 4:6)];
Y_telem = datos_todos(:, 7:13);
W = datos_todos(:, end);
modelos_aux = cell(7,1);

for j = 1:7
    modelos_aux{j} = fitrensemble(X_aux, Y_telem(:,j), 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 10), 'NumLearningCycles', 100, 'Weights', W);
end

%% Modelo principal
X_global = [];
for k = 1:size(datos_todos, 1)
    fw = datos_todos(k,1);
    rw = datos_todos(k,2);
    geo = datos_todos(k,4:6);
    telem = datos_todos(k,7:13);
    features = [fw, rw, geo, telem];
    X_global = [X_global; features];
end

[X_norm, mu_feat, sigma_feat] = zscore(X_global);
sigma_feat(sigma_feat==0) = 1;
Y_global = datos_todos(:, 3);
W = datos_todos(:, end);

% Entrenar modelo principal
modelo = fitrensemble(X_norm, Y_global, 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 15), 'NumLearningCycles', 126, 'LearnRate', 0.15, 'Weights', W);

%% Validación 5-Fold Cross 
K = 5;
n = size(X_norm, 1);
cv = cvpartition(n, 'KFold', K);
pred_all = NaN(n, 1);  
r2_folds = zeros(K, 1);
mae_folds = zeros(K, 1);
for fold = 1:K
    train = training(cv, fold);
    prueba = test(cv, fold);
    
    modelo_fold = fitrensemble(X_norm(train, :), Y_global(train), 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 15), 'NumLearningCycles', 126, 'LearnRate', 0.15, 'Weights', W(train));
    
    pred_fold = predict(modelo_fold, X_norm(prueba, :));
    pred_all(prueba) = pred_fold;
    
    Y_test = Y_global(prueba);
    r2_folds(fold) = 1 - sum((Y_test - pred_fold).^2) / sum((Y_test - mean(Y_test)).^2);
    mae_folds(fold) = mean(abs(Y_test - pred_fold));
end
r2 = mean(r2_folds);
r2_std = std(r2_folds);
mae = mean(mae_folds);

%% Guardar modelo 
modelosPath = fullfile(pathToApp, folderModelos);
if ~exist(modelosPath, 'dir'), mkdir(modelosPath); end
save(fullfile(modelosPath, 'modeloML.mat'), 'modelo', 'modelos_aux', 'mu_feat', 'sigma_feat', 'circuitos');
resultado.success = true;
resultado.r2 = r2;
resultado.r2_std = r2_std;
resultado.mae = mae;
resultado.nCircuitos = length(circuitos);
resultado.numVueltas = size(datos_todos, 1);
resultado.Targets = Y_global;       
resultado.Predictions = pred_all;   
end