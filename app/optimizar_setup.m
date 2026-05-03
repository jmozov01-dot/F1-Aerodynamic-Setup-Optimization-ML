function resultado = optimizar_setup(pathToApp, circuitoSeleccionado, temporada)
    resultado = struct();
    
    if nargin < 3, temporada = '2025'; end
    if strcmp(temporada, '2026')
        folderDatos = 'datos_2026'; folderModelos = 'modelos_2026';
    else
        folderDatos = 'datos'; folderModelos = 'modelos';
    end
    datosPath = fullfile(pathToApp, folderDatos);
    modelosPath = fullfile(pathToApp, folderModelos);

%% PASO 5: Optimización Setup
load(fullfile(modelosPath, 'modeloML.mat'), 'modelo', 'modelos_aux', 'mu_feat', 'sigma_feat');
circuito = circuitoSeleccionado;
circuit_data = load(fullfile(datosPath, sprintf('circuit_%s.mat', circuito))).circuit_data;
laps = load(fullfile(datosPath, sprintf('laps_%s.mat', circuito))).laps.lap_data;
laps = laps(laps(:,2)>0, :);
mu_local = mean(laps(:,2));
sigma_local = std(laps(:,2));

if sigma_local == 0
    sigma_local = 1;
end

curv = abs(circuit_data.curvature);
n = length(curv);
r_rectas = sum(curv < 0.002) / n;
r_rapidas = sum(curv >= 0.002 & curv < 0.006) / n;
r_lentas = sum(curv >= 0.006) / n;

results = [];

% Rangos según temporada
    if strcmp(temporada, '2026')
        rango_fw = 10:1:30;  
        rango_rw = 0:5:20;    
    else
        % 2025
        rango_fw = 10:1:30;
        rango_rw = 10:5:30;
    end
    for fw = rango_fw
        for rw = rango_rw

            if strcmp(temporada, '2026')
                balance = fw - 10 - rw;
                if balance < -5 || balance > 5
                    continue;
                end
            else
                balance = fw - rw;
                if balance < -4 || balance > 7
                    continue;
                end
            end

        
        X_geo = [fw, rw, r_rectas, r_rapidas, r_lentas];
        telem = zeros(1,7);
        for k = 1:7
            telem(k) = predict(modelos_aux{k}, X_geo);
        end
        
        features = [fw, rw, r_rectas, r_rapidas, r_lentas, telem];
        features_norm = (features - mu_feat) ./ sigma_feat;
        z_pred = predict(modelo, features_norm);
        t_est = z_pred * sigma_local + mu_local;
        
        results = [results; fw, rw, z_pred, t_est, telem];
        end
    end

[~, idx] = sort(results(:,3));
results = results(idx, :);

setups = unique(laps(:,4:5), 'rows');
best_time = inf;
best_setup = [NaN NaN];
for i = 1:size(setups,1)
    mask = laps(:,4)==setups(i,1) & laps(:,5)==setups(i,2);
    t = min(laps(mask,2));
    if t < best_time
        best_time = t;
        best_setup = setups(i,:);
    end
end
    resultado.TopSetups = results;
    resultado.BestRealTime = best_time;
    resultado.BestRealSetup = best_setup;
    resultado.Geometria = [r_rectas, r_rapidas, r_lentas];
end