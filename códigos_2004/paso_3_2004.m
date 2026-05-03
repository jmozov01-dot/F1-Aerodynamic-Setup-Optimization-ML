%% PASO 3: Extracción de telemetría completa
clear; clc;

%% Selección carpeta
folder = uigetdir(pwd, 'Seleccionar carpeta con archivos de telemetría');
if folder == 0
    disp('Cancelado');
    return;
end
% Detectar circuito
[~, foldername] = fileparts(folder);
parts = strsplit(lower(foldername), ' ');
circuito = parts{end};
if contains(circuito, 'telemetria')
    circuito = parts{1};
end
fprintf('\nCircuito: %s\n', circuito);
% Verificar archivo laps
laps_file = fullfile('datos_2004', sprintf('laps_%s.mat', circuito));
if ~isfile(laps_file)
    fprintf('No existe %s\n', laps_file);
    return;
end
load(laps_file);
lap_mapping = laps.mapping;
% Buscar archivos
files = dir(fullfile(folder, '*.csv'));
fprintf('Archivos: %d\n\n', length(files));
%% Inicializar telemetría
telemetry = struct();
telemetry.fw = []; telemetry.rw = [];
telemetry.hf = []; telemetry.hr = [];
telemetry.speed = []; telemetry.glat = []; telemetry.glong = [];
telemetry.acelerador = []; telemetry.freno = []; telemetry.steering = [];
telemetry.lap_id = [];
telemetry.car_x = []; telemetry.car_y = []; telemetry.car_z = [];
telemetry.distance = [];
total_muestras = 0;

%% Procesar archivos 
nFiles = length(files);
telemetry_parts = cell(nFiles, 1);

parfor f = 1:nFiles
    filename = fullfile(files(f).folder, files(f).name);
    
    file_data = lap_mapping(lap_mapping(:,1) == f, :);
    lap_map = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = 1:size(file_data, 1)
        lap_map(file_data(i,2)) = file_data(i,3);
    end
    
    try
        fid = fopen(filename, 'r');
        lines = {};
        while ~feof(fid)
            l = fgetl(fid);
            if ischar(l)
                lines{end+1} = l;
            end
        end
        fclose(fid);
        
        setup = strsplit(lines{17}, ';', 'CollapseDelimiters', false);
        fw = str2double(setup{6});  
        rw = str2double(setup{7});  
        hf = str2double(setup{4});  
        hr = str2double(setup{5});
        
        muestras = 0;
        dist_acum = 0;
        last_x = NaN; last_y = NaN; last_z = NaN;
        
        temp_data = struct();
        temp_data.speed = []; temp_data.glat = []; temp_data.glong = [];
        temp_data.acelerador = []; temp_data.freno = []; temp_data.steering = [];
        temp_data.lap_id = [];
        temp_data.car_x = []; temp_data.car_y = []; temp_data.car_z = [];
        temp_data.distance = [];
        
        contador_vuelta = 1;
        tiempo_anterior = -1;
        muestras_cambio = 1000;

        for row = 22:length(lines)
            data = strsplit(lines{row}, ';', 'CollapseDelimiters', false);
            
            if length(data) < 121, continue; end
            
            try
                tiempo_actual = str2double(data{86});
                if ~isnan(tiempo_actual)
                if tiempo_anterior > 0 && (tiempo_actual < tiempo_anterior - 10) && muestras_cambio > 300
                    contador_vuelta = contador_vuelta + 1;
                    muestras_cambio = 0;
                end

                muestras_cambio = muestras_cambio + 1;
                tiempo_anterior = tiempo_actual;
                end
                lap_num = contador_vuelta; 

                speed = str2double(data{85});
                acelerador = str2double(data{89});
                freno = str2double(data{90});
                steering_deg = str2double(data{92});
                glat = str2double(data{120});
                glong = str2double(data{121});
                
                car_x = str2double(data{117});
                car_y = str2double(data{118});
                car_z = str2double(data{119});
                
                if isnan(speed) || speed < 30 || speed > 350, continue; end
                if isnan(acelerador) || acelerador < 0 || acelerador > 100, continue; end
                if isnan(freno) || freno < 0 || freno > 100, continue; end
                if isnan(glat) || glat < -7 || glat > 7, continue; end
                if isnan(glong) || glong < -7 || glong > 3, continue; end
                if isnan(steering_deg) || steering_deg < -300 || steering_deg > 300, continue; end
                if isnan(car_x) || isnan(car_y) || isnan(car_z), continue; end
                
                lap_num_floor = floor(lap_num);
                
                if isKey(lap_map, lap_num_floor)
                    lap_id_mapped = lap_map(lap_num_floor);
                    
                    if ~isnan(last_x)
                        dx = car_x - last_x;
                        dy = car_y - last_y;
                        dz = car_z - last_z;
                        dist_acum = dist_acum + sqrt(dx^2 + dy^2 + dz^2);
                    end
                    
                    last_x = car_x; last_y = car_y; last_z = car_z;
                    
                    temp_data.speed(end+1) = speed;
                    temp_data.acelerador(end+1) = acelerador;
                    temp_data.freno(end+1) = freno;
                    temp_data.steering(end+1) = steering_deg;
                    temp_data.glat(end+1) = glat;
                    temp_data.glong(end+1) = glong;
                    temp_data.lap_id(end+1) = lap_id_mapped;
                    temp_data.car_x(end+1) = car_x;
                    temp_data.car_y(end+1) = car_y;
                    temp_data.car_z(end+1) = car_z;
                    temp_data.distance(end+1) = dist_acum;
                    
                    muestras = muestras + 1;
                end
                
            catch
                continue;
            end
        end
        
        temp_data.fw = repmat(fw, 1, muestras);
        temp_data.rw = repmat(rw, 1, muestras);
        temp_data.hf = repmat(hf, 1, muestras);
        temp_data.hr = repmat(hr, 1, muestras);
        temp_data.muestras = muestras;
        
        telemetry_parts{f} = temp_data;
        
    catch
        telemetry_parts{f} = [];
    end
end

%% Unir resultados
for f = 1:nFiles
    if isempty(telemetry_parts{f})
        fprintf('Archivo %d: error\n\n', f);
        continue;
    end
    temp_data = telemetry_parts{f};
    if temp_data.muestras == 0
        continue;
    end
    
    fprintf('Archivo %d\n', f);
    fprintf('Setup: FW=%d, RW=%d, HF=%d, HR=%d\n', temp_data.fw(1), temp_data.rw(1), temp_data.hf(1), temp_data.hr(1));
    fprintf('Muestras: %d\n', temp_data.muestras);
    fprintf('Telemetría:\n');
    fprintf(' Velocidad:  %.1f - %.1f km/h (media: %.1f)\n', min(temp_data.speed), max(temp_data.speed), mean(temp_data.speed));
    fprintf(' Acelerador: %.1f - %.1f %% (media: %.1f)\n', min(temp_data.acelerador), max(temp_data.acelerador), mean(temp_data.acelerador));
    fprintf(' Freno:      %.1f - %.1f %% (media: %.1f)\n', min(temp_data.freno), max(temp_data.freno), mean(temp_data.freno));
    fprintf(' G lateral:  %.2f - %.2f g (media: %.2f)\n', min(temp_data.glat), max(temp_data.glat), mean(temp_data.glat));
    fprintf(' G longitudinal: %.2f - %.2f g (media: %.2f)\n', min(temp_data.glong), max(temp_data.glong), mean(temp_data.glong));
    fprintf('\n');
    
    telemetry.fw = [telemetry.fw, temp_data.fw];
    telemetry.rw = [telemetry.rw, temp_data.rw];
    telemetry.hf = [telemetry.hf, temp_data.hf];
    telemetry.hr = [telemetry.hr, temp_data.hr];
    telemetry.speed = [telemetry.speed, temp_data.speed];
    telemetry.glat = [telemetry.glat, temp_data.glat];
    telemetry.glong = [telemetry.glong, temp_data.glong];
    telemetry.acelerador = [telemetry.acelerador, temp_data.acelerador];
    telemetry.freno = [telemetry.freno, temp_data.freno];
    telemetry.steering = [telemetry.steering, temp_data.steering];
    telemetry.lap_id = [telemetry.lap_id, temp_data.lap_id];
    telemetry.car_x = [telemetry.car_x, temp_data.car_x];
    telemetry.car_y = [telemetry.car_y, temp_data.car_y];
    telemetry.car_z = [telemetry.car_z, temp_data.car_z];
    telemetry.distance = [telemetry.distance, temp_data.distance];
    
    total_muestras = total_muestras + temp_data.muestras;
end

%% Métricas por vuelta 
unique_laps = unique(telemetry.lap_id);
n_laps = length(unique_laps);
lap_metrics = struct();
lap_metrics.glat_media = zeros(1, n_laps);
lap_metrics.glong_freno = zeros(1, n_laps);    
lap_metrics.glong_acel = zeros(1, n_laps);    
lap_metrics.v_max = zeros(1, n_laps);
lap_metrics.t_freno = zeros(1, n_laps);
lap_metrics.t_acelerador = zeros(1, n_laps);
lap_metrics.steering_std = zeros(1, n_laps);
lap_metrics.lap_id = zeros(1, n_laps);
fprintf('Calculando métricas...\n');

for i = 1:n_laps
    mask = telemetry.lap_id == unique_laps(i);
    v = telemetry.speed(mask);
    glat = telemetry.glat(mask);
    glong = telemetry.glong(mask); 
    acelerador = telemetry.acelerador(mask) / 100;
    freno = telemetry.freno(mask) / 100;
    n_samples = sum(mask);
            
    curva_mask = abs(glat) > 0.5;
    if any(curva_mask)
       lap_metrics.glat_media(i) = mean(abs(glat(curva_mask)));
    else
       lap_metrics.glat_media(i) = mean(abs(glat)); 
    end

    % Fuerza longitudinal frenando (negativa)
    neg_mask = glong < 0;
    if any(neg_mask)
    lap_metrics.glong_freno(i) = mean(glong(neg_mask));
    else
    lap_metrics.glong_freno(i) = 0;
    end
    % Fuerza longitudinal acelerando (positiva)
    pos_mask = glong >= 0;
    if any(pos_mask)
    lap_metrics.glong_acel(i) = mean(glong(pos_mask));
    else
    lap_metrics.glong_acel(i) = 0;
    end

    lap_metrics.v_max(i) = max(v);
    
    freno_mask = freno > 0.10;
    lap_metrics.t_freno(i) = sum(freno_mask) / n_samples;
    
    t_acelerador_mask = acelerador > 0.95;
    lap_metrics.t_acelerador(i) = sum(t_acelerador_mask) / n_samples;

    lap_metrics.steering_std(i) = std(telemetry.steering(mask));
    
    lap_metrics.lap_id(i) = unique_laps(i);
    
    if mod(i,10)==0
        fprintf('  %d/%d vueltas\n', i, n_laps);
    end
end
telemetry.lap_metrics = lap_metrics;
fprintf('Métricas: %d vueltas\n', n_laps);
fprintf('\nResumen métricas:\n');
fprintf('glat_media: [%.2f - %.2f] g\n', min(lap_metrics.glat_media), max(lap_metrics.glat_media));
fprintf('glong_freno: [%.2f - %.2f] g\n', min(lap_metrics.glong_freno), max(lap_metrics.glong_freno));
fprintf('glong_acel: [%.2f - %.2f] g\n', min(lap_metrics.glong_acel), max(lap_metrics.glong_acel));
fprintf('v_max: [%.1f - %.1f] km/h\n', min(lap_metrics.v_max), max(lap_metrics.v_max));
fprintf('t_freno: [%.1f - %.1f] %%\n', min(lap_metrics.t_freno)*100, max(lap_metrics.t_freno)*100);
fprintf('t_acelerador: [%.1f - %.1f] %%\n', min(lap_metrics.t_acelerador)*100, max(lap_metrics.t_acelerador)*100);
fprintf('steering_std: [%.1f - %.1f] º\n', min(lap_metrics.steering_std), max(lap_metrics.steering_std));
%% Guardar
if total_muestras == 0
    fprintf('No hay muestras\n');
    return;
end
save_file = fullfile('datos_2004', sprintf('telemetry_%s.mat', circuito));
save(save_file, 'telemetry');
fprintf('\nTotal: %d muestras\n', total_muestras);
fprintf('Guardado: %s\n', save_file);