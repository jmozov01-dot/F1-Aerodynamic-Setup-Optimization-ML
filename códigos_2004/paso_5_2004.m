%% PASO 5: Optimización Setup
clear; clc;
fprintf('\nPASO 5: Optimización Setup\n\n');

load(fullfile('modelos_2004', 'modeloML.mat'), 'modelo', 'modelos_aux', 'mu_feat', 'sigma_feat');

files = dir(fullfile('datos_2004', 'circuit_*.mat'));
available = {};
for i = 1:length(files)
    nombre = strrep(strrep(files(i).name, 'circuit_',''), '.mat','');
    if exist(fullfile('datos_2004', sprintf('laps_%s.mat', nombre)), 'file')
        available{end+1} = nombre;
    end
end

fprintf('Circuitos disponibles:\n');
for i = 1:length(available)
    fprintf('  %d. %s\n', i, upper(available{i}));
end

idx = input('\nSelecciona circuito: ');
circuito = available{idx};

circuit_data = load(fullfile('datos_2004', sprintf('circuit_%s.mat', circuito))).circuit_data;
laps = load(fullfile('datos_2004', sprintf('laps_%s.mat', circuito))).laps.lap_data;
laps = laps(laps(:,2)>0, :);
mu_local = mean(laps(:,2));
sigma_local = std(laps(:,2));
if sigma_local == 0, sigma_local = 1; end

curv = abs(circuit_data.curvature);
n = length(curv);
r_rectas = sum(curv < 0.002) / n;
r_rapidas = sum(curv >= 0.002 & curv < 0.006) / n;
r_lentas = sum(curv >= 0.006) / n;

fprintf('\nCircuito: %s\n', upper(circuito));
fprintf('Geometría: %.1f%% rectas, %.1f%% rápidas, %.1f%% lentas\n', r_rectas*100, r_rapidas*100, r_lentas*100);
fprintf('\nSimulando setups...\n');

results = [];
parfor fw = 0:30
    resultados_local = []; 
    
    for rw = 5:1:35
        balance = fw - rw + 5;
        if balance < -4 || balance > 8, continue; end
    for hf = 0:10:40
        for hr = 0:10:60
        if hf > hr, continue; end 
                
                X_geo = [fw, rw, hf, hr, r_rectas, r_rapidas, r_lentas];
                telem = zeros(1,7);
                for k = 1:7
                    telem(k) = predict(modelos_aux{k}, X_geo);
                end
                
                features = [fw, rw, hf, hr, r_rectas, r_rapidas, r_lentas, telem];
                features_norm = (features - mu_feat) ./ sigma_feat;
                z_pred = predict(modelo, features_norm);
                t_est = z_pred * sigma_local + mu_local;
                
                resultados_local = [resultados_local; fw, rw, hf, hr, z_pred, t_est];
         end
     end
   end
    results = [results; resultados_local];
end

[~, idx_sort] = sort(results(:,5));
results = results(idx_sort, :);

fprintf('\nTop 10 (%s):\n', upper(circuito));
fprintf('   #  FW (º)  RW (º)  HF (mm)  HR (mm)   Z-Score    Tiempo (s)   Balance\n');
for i = 1:min(20, size(results,1))
    fw = results(i,1); 
    rw = results(i,2);
    hf = results(i,3); 
    hr = results(i,4);
    fprintf('  %2d   %2d      %2d      %2d      %2d     %+9.3f     %8.3fs      %+d\n', i, fw, rw, hf, hr, results(i,5), results(i,6), (fw-rw+5));
end

% Mejor vuelta real
setups = unique(laps(:,4:7), 'rows');
best_time = inf; best_setup = [NaN NaN NaN NaN];
for i = 1:size(setups,1)
    mask = laps(:,4)==setups(i,1) & laps(:,5)==setups(i,2) & laps(:,6)==setups(i,3) & laps(:,7)==setups(i,4);
    t = min(laps(mask,2));
    if t < best_time
        best_time = t; 
        best_setup = setups(i,:); 
    end
end
fprintf('\nMejor vuelta real: FW=%d RW=%d HF=%d HR=%d (%.3fs)\n', best_setup(1), best_setup(2), best_setup(3), best_setup(4), best_time);