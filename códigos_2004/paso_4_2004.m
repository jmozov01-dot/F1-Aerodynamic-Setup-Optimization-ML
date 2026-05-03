%% PASO 4: Modelo ML
clear; clc;
rng(1);
fprintf('\nPASO 4: Modelo ML\n\n');

%% Cargar datos
files = dir(fullfile('datos_2004', 'circuit_*.mat'));
circuitos = {};
datos_todos = [];
fprintf('Cargando circuitos...\n');

% Calcular pesos automáticos
vueltas_por_circuito = containers.Map();
for i = 1:length(files)
    nombre = strrep(strrep(files(i).name, 'circuit_',''), '.mat','');
    laps_file = fullfile('datos_2004', sprintf('laps_%s.mat', nombre));
    if exist(laps_file, 'file')
        temp_laps = load(laps_file).laps.lap_data;
        vueltas_por_circuito(nombre) = sum(temp_laps(:,2) > 0);
    end
end
max_vueltas = max(cell2mat(values(vueltas_por_circuito)));

for i = 1:length(files)
    nombre = strrep(strrep(files(i).name, 'circuit_',''), '.mat','');
    
    if ~exist(fullfile('datos_2004', sprintf('laps_%s.mat', nombre)), 'file') || ~exist(fullfile('datos_2004', sprintf('telemetry_%s.mat', nombre)), 'file')
        continue;
    end
    
    circuitos{end+1} = nombre;
    
    circuit_data = load(fullfile('datos_2004', sprintf('circuit_%s.mat', nombre))).circuit_data;
    laps = load(fullfile('datos_2004', sprintf('laps_%s.mat', nombre))).laps.lap_data;
    telemetry = load(fullfile('datos_2004', sprintf('telemetry_%s.mat', nombre))).telemetry;
    
    curv = abs(circuit_data.curvature);
    n_pts = length(curv);
    r_rectas = sum(curv < 0.002) / n_pts;
    r_rapidas = sum(curv >= 0.002 & curv < 0.006) / n_pts;
    r_lentas = sum(curv >= 0.006) / n_pts;
    
    tiempos = laps(laps(:,2)>0, 2);
    mu_local = mean(tiempos);
    sigma_local = std(tiempos);
    if sigma_local == 0
        sigma_local = 1;
    end
    
    for k = 1:size(laps, 1)
        fw = laps(k,4);
        rw = laps(k,5);
        hf = laps(k,6);
        hr = laps(k,7);
        tiempo = laps(k,2);
        lap_id = laps(k,1);
        
        if tiempo <= 0
            continue;
        end
        
        idx = find(telemetry.lap_metrics.lap_id == lap_id, 1);
        if isempty(idx)
            continue;
        end
        
        tm = telemetry.lap_metrics;
        telem = [tm.v_max(idx), tm.glat_media(idx), tm.glong_acel(idx), tm.glong_freno(idx), tm.t_acelerador(idx), tm.t_freno(idx), tm.steering_std(idx)];
        z_score = (tiempo - mu_local) / sigma_local;
        
        w = max_vueltas / vueltas_por_circuito(nombre); % Peso por circuito
        
         fila = [fw, rw, hf, hr, z_score, r_rectas, r_rapidas, r_lentas, telem, mu_local, sigma_local, w];
        datos_todos = [datos_todos; fila];
    end
    
    fprintf('%12s: %3d vueltas\n', upper(nombre), size(laps,1));
end
fprintf('\nTotal: %d circuitos, %d vueltas\n', length(circuitos), size(datos_todos,1));

%% Modelos auxiliares
fprintf('\nModelos auxiliares...\n');
X_aux = [datos_todos(:, 1:4), datos_todos(:, 6:8)];
Y_telem = datos_todos(:, 9:15);
W = datos_todos(:, end);
modelos_aux = cell(7,1);

for j = 1:7
    modelos_aux{j} = fitrensemble(X_aux, Y_telem(:,j), 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 10), 'NumLearningCycles', 100, 'Weights', W);
end

%% Modelo principal
fprintf('\nModelo principal...\n');
X_global = [];

for k = 1:size(datos_todos, 1)
    fw = datos_todos(k,1);
    rw = datos_todos(k,2);
    hf = datos_todos(k,3);
    hr = datos_todos(k,4);
    geo = datos_todos(k,6:8);
    telem = datos_todos(k,9:15);
    features = [fw, rw, hf, hr, geo, telem];
    X_global = [X_global; features];
end

[X_norm, mu_feat, sigma_feat] = zscore(X_global);
sigma_feat(sigma_feat==0) = 1;
Y_global = datos_todos(:, 5);
W = datos_todos(:, end);

% Entrenar modelo principal
modelo = fitrensemble(X_norm, Y_global, 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 3), 'NumLearningCycles', 302, 'LearnRate', 0.0743, 'Weights', W); % Valores obtenidos tras optimizar hiperparámetros

%% Validación 5-Fold Cross Validation
K = 5;
n = size(X_norm, 1);
cv = cvpartition(n, 'KFold', K);
r2_folds = zeros(K, 1);
mae_folds = zeros(K, 1); 

for fold = 1:K
    train = training(cv, fold);
    prueba = test(cv, fold);
    
    modelo_fold = fitrensemble(X_norm(train, :), Y_global(train), 'Method', 'LSBoost', 'Learners', templateTree('MaxNumSplits', 15), 'NumLearningCycles', 126, 'LearnRate', 0.15, 'Weights', W(train));
    
    pred_fold = predict(modelo_fold, X_norm(prueba, :));
    Y_test = Y_global(prueba);
    
    r2_folds(fold) = 1 - sum((Y_test - pred_fold).^2) / sum((Y_test - mean(Y_test)).^2);
    
    mae_folds(fold) = mean(abs(Y_test - pred_fold));
end

fprintf('R² por fold: '); fprintf('%.4f  ', r2_folds); fprintf('\n');
fprintf('R² (5-Fold CV): %.4f ± %.4f\n', mean(r2_folds), std(r2_folds));
fprintf('MAE por fold: '); fprintf('%.4f  ', mae_folds); fprintf('\n');
fprintf('MAE (5-Fold CV): %.4f ± %.4f\n', mean(mae_folds), std(mae_folds));

%% Guardar
if ~exist('modelos_2004', 'dir')
    mkdir('modelos_2004');
end
save(fullfile('modelos_2004', 'modeloML.mat'), 'modelo', 'modelos_aux', 'mu_feat', 'sigma_feat', 'circuitos');
fprintf('\nGuardado.\n');

%% Importancia
imp = predictorImportance(modelo);
nombres = {'fw','rw','hf','hr','r_rectas','r_rapidas','r_lentas','v_max','glat_media','glong_acel','glong_freno','t_acelerador','t_freno','steering_std'};
[imp_ord, idx] = sort(imp, 'descend');
fprintf('\nImportancia features:\n');
for i = 1:length(idx)
    fprintf('  %2d. %-13s: %.4f\n', i, nombres{idx(i)}, imp_ord(i));
end

