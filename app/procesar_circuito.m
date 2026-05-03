function resultado = procesar_circuito(circuito, pathToApp, temporada)
resultado = struct();
resultado.success = false;
try
    
    %% PASO 1: Cargar circuito OpenTRACK
    circuitoCapital = [upper(circuito(1)), circuito(2:end)];
    trackFolder = fullfile(pathToApp, 'circuitos opentrack');
    trackFiles = dir(fullfile(trackFolder, sprintf('OpenTRACK_%s*.mat', circuitoCapital)));
    
    if isempty(trackFiles)
        return;
    end
    
    matdata = load(fullfile(trackFiles(1).folder, trackFiles(1).name));
    
    X = matdata.X; Y = matdata.Y; Z = matdata.Z;
    r = matdata.r; bank = matdata.bank; incl = matdata.incl;
    factor_grip = matdata.factor_grip; dx = matdata.dx;
    
    distance = cumsum(dx);
    distance = [0; distance(1:end-1)];
    
    info = matdata.info;
    circuit_data.name = info.name;
    circuit_data.country = info.country;
    circuit_data.distance = distance(end);
    circuit_data.n_points = matdata.n;
    circuit_data.X = X; circuit_data.Y = Y; circuit_data.Z = Z;
    circuit_data.distance_array = distance;
    circuit_data.curvature = r; circuit_data.bank = bank;
    circuit_data.incline = incl; circuit_data.grip_factor = factor_grip;
    circuit_data.dx = dx;
    
    if nargin < 3, temporada = '2025'; end
    if strcmp(temporada, '2026')
        datosFolder = fullfile(pathToApp, 'datos_2026');
    else
        datosFolder = fullfile(pathToApp, 'datos');
    end
    if ~exist(datosFolder, 'dir'), mkdir(datosFolder); end
    save(fullfile(datosFolder, sprintf('circuit_%s.mat', circuito)), 'circuit_data');
    
    %% PASO 2: Extraer tiempos de vuelta
    if strcmp(temporada, '2026')
        telemetriaFolder = fullfile(pathToApp, 'telemetrias_2026', sprintf('telemetria 2026 %s', circuito));
    else
        telemetriaFolder = fullfile(pathToApp, 'telemetrias', sprintf('telemetria %s', circuito));
    end

    if ~exist(telemetriaFolder, 'dir')
        error('No hay datos');
    end
    
    files = dir(fullfile(telemetriaFolder, '*.csv'));
    if isempty(files)
        error('No hay datos');
    end
    
    all_laps = [];
    lap_mapping = [];
    lap_id = 0;
    
    for f = 1:length(files)
        filename = fullfile(files(f).folder, files(f).name);
        try
            fid = fopen(filename, 'r');
            for i = 1:17, line = fgetl(fid); end
            fclose(fid);
            
            setup = strsplit(line, ';', 'CollapseDelimiters', false);
            fw = str2double(setup{76});
            rw = str2double(setup{77});
            
            data = readtable(filename, 'Delimiter', ';', 'HeaderLines', 21, 'ReadVariableNames', false);

            if strcmp(temporada, '2026')
                lap_times = data.Var91;
            else
                lap_times = data.Var93;
            end
            
            if iscell(lap_times) || isstring(lap_times)
                lap_times = str2double(lap_times);
            end
            
            valid = ~isnan(lap_times);
            lap_times = lap_times(valid);
            
            lap_change = find(diff(lap_times) < -10);

            if ~isempty(lap_change)
                keep_mask = [true; diff(lap_change) > 300]; 
                lap_change = lap_change(keep_mask);
            end
            
            finales_vuelta = [lap_change; length(lap_times)];
            
            vueltas = [];
            for k = 1:length(finales_vuelta)
                idx_fin = finales_vuelta(k);
                tiempo_final = lap_times(idx_fin);
                numero_virtual = k; 
                vueltas = [vueltas; numero_virtual, tiempo_final];
            end
            
            if strcmp(temporada, '2026')
                vueltas = vueltas(vueltas(:,1) >= 0 & vueltas(:,2) > 70 & vueltas(:,2) < 114, :);
            else
                vueltas = vueltas(vueltas(:,1) >= 0 & vueltas(:,2) > 60 & vueltas(:,2) < 120, :);
            end
            
            for i = 1:size(vueltas, 1)
                lap_id = lap_id + 1;
                all_laps = [all_laps; lap_id, vueltas(i,2), f, fw, rw];
                lap_mapping = [lap_mapping; f, vueltas(i,1), lap_id];
            end
        catch
        end
    end

    if isempty(all_laps)
        error('Error');
    end
    
    laps.lap_data = all_laps;
    laps.mapping = lap_mapping;
    save(fullfile(datosFolder, sprintf('laps_%s.mat', circuito)), 'laps');
    
    %% PASO 3: Extraer telemetría
    telemetry = struct();
    telemetry.fw = []; telemetry.rw = [];
    telemetry.speed = []; telemetry.glat = []; telemetry.glong = [];
    telemetry.acelerador = []; telemetry.freno = []; telemetry.steering = [];
    telemetry.lap_id = [];
    telemetry.car_x = []; telemetry.car_y = []; telemetry.car_z = [];
    telemetry.distance = [];
    total_muestras = 0;
    
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
                if ischar(l), lines{end+1} = l; end
            end
            fclose(fid);
            
            setup = strsplit(lines{17}, ';', 'CollapseDelimiters', false);
            fw = str2double(setup{76});
            rw = str2double(setup{77});
            
            muestras = 0;
            dist_acum = 0;
            last_x = NaN; last_y = NaN; last_z = NaN;
            
            temp = struct();
            temp.speed = []; temp.glat = []; temp.glong = [];
            temp.acelerador = []; temp.freno = []; temp.steering = [];
            temp.lap_id = [];
            temp.car_x = []; temp.car_y = []; temp.car_z = [];
            temp.distance = [];
            
            contador_vuelta = 1;
            tiempo_anterior = -1;
            muestras_cambio = 1000;

            for row = 22:length(lines)
                data = strsplit(lines{row}, ';', 'CollapseDelimiters', false);
                
                try 
                    if strcmp(temporada, '2026')
                        if length(data) < 126, continue; end
                        
                        tiempo_actual = str2double(data{91});
                        if ~isnan(tiempo_actual)
                            if tiempo_anterior > 0 && (tiempo_actual < tiempo_anterior - 10) && muestras_cambio > 300
                                contador_vuelta = contador_vuelta + 1;
                                muestras_cambio = 0;
                            end
                            muestras_cambio = muestras_cambio + 1;
                            tiempo_anterior = tiempo_actual;
                        end
                        lap_num = contador_vuelta; 

                        speed = str2double(data{90});
                        acelerador = str2double(data{94});
                        freno = str2double(data{95});
                        steering_deg = str2double(data{97});
                        glat = str2double(data{125});
                        glong = str2double(data{126});
                        
                        car_x = str2double(data{122});
                        car_y = str2double(data{123});
                        car_z = str2double(data{124});
                        
                    else
                        if length(data) < 128, continue; end
                        
                        tiempo_actual = str2double(data{93});
                        if ~isnan(tiempo_actual)
                            if tiempo_anterior > 0 && (tiempo_actual < tiempo_anterior - 10) && muestras_cambio > 300
                                contador_vuelta = contador_vuelta + 1;
                                muestras_cambio = 0;
                            end
                            muestras_cambio = muestras_cambio + 1;
                            tiempo_anterior = tiempo_actual;
                        end
                        lap_num = contador_vuelta; 

                        speed = str2double(data{92});
                        acelerador = str2double(data{96});
                        freno = str2double(data{97});
                        steering_deg = str2double(data{99});
                        glat = str2double(data{127});
                        glong = str2double(data{128});
                        
                        car_x = str2double(data{124});
                        car_y = str2double(data{125});
                        car_z = str2double(data{126});
                    end

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
                            dist_acum = dist_acum + sqrt((car_x-last_x)^2 + (car_y-last_y)^2 + (car_z-last_z)^2);
                        end
                        last_x = car_x; last_y = car_y; last_z = car_z;
                        
                        temp.speed(end+1) = speed;
                        temp.acelerador(end+1) = acelerador;
                        temp.freno(end+1) = freno;
                        temp.steering(end+1) = steering_deg;
                        temp.glat(end+1) = glat;
                        temp.glong(end+1) = glong;
                        temp.lap_id(end+1) = lap_id_mapped;
                        temp.car_x(end+1) = car_x;
                        temp.car_y(end+1) = car_y;
                        temp.car_z(end+1) = car_z;
                        temp.distance(end+1) = dist_acum;
                        muestras = muestras + 1;
                    end
                catch
                end
            end
            
            temp.fw = repmat(fw, 1, muestras);
            temp.rw = repmat(rw, 1, muestras);
            temp.muestras = muestras;
            
            telemetry_parts{f} = temp;
        catch
            telemetry_parts{f} = [];
        end
    end
    
    %% Unir resultados
    for f = 1:nFiles
        if isempty(telemetry_parts{f})
            continue;
        end
        temp = telemetry_parts{f};
        if temp.muestras == 0
            continue;
        end
        
        telemetry.fw = [telemetry.fw, temp.fw];
        telemetry.rw = [telemetry.rw, temp.rw];
        telemetry.speed = [telemetry.speed, temp.speed];
        telemetry.glat = [telemetry.glat, temp.glat];
        telemetry.glong = [telemetry.glong, temp.glong];
        telemetry.acelerador = [telemetry.acelerador, temp.acelerador];
        telemetry.freno = [telemetry.freno, temp.freno];
        telemetry.steering = [telemetry.steering, temp.steering];
        telemetry.lap_id = [telemetry.lap_id, temp.lap_id];
        telemetry.car_x = [telemetry.car_x, temp.car_x];
        telemetry.car_y = [telemetry.car_y, temp.car_y];
        telemetry.car_z = [telemetry.car_z, temp.car_z];
        telemetry.distance = [telemetry.distance, temp.distance];
        total_muestras = total_muestras + temp.muestras;
    end
    
    % Métricas por vuelta
    if total_muestras > 0
        unique_laps = unique(telemetry.lap_id);
        n_laps = length(unique_laps);
        
        lap_metrics.glat_media = zeros(1, n_laps);
        lap_metrics.glong_freno = zeros(1, n_laps);    
        lap_metrics.glong_acel = zeros(1, n_laps);    
        lap_metrics.v_max = zeros(1, n_laps);
        lap_metrics.t_freno = zeros(1, n_laps);
        lap_metrics.t_acelerador = zeros(1, n_laps);
        lap_metrics.steering_std = zeros(1, n_laps);
        lap_metrics.lap_id = zeros(1, n_laps);
        
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

            lap_metrics.t_freno(i) = sum(freno > 0.05) / n_samples;
            lap_metrics.t_acelerador(i) = sum(acelerador > 0.95) / n_samples;

            lap_metrics.steering_std(i) = std(telemetry.steering(mask));

            lap_metrics.lap_id(i) = unique_laps(i);
        end
        telemetry.lap_metrics = lap_metrics;
    end

    if total_muestras == 0
        error('Error');
    end
    
    save(fullfile(datosFolder, sprintf('telemetry_%s.mat', circuito)), 'telemetry');
    
    resultado.success = true;
    resultado.nVueltas = size(all_laps, 1);
    resultado.nMuestras = total_muestras;
    
catch ME
        if exist('datosFolder', 'var') && exist(fullfile(datosFolder, sprintf('circuit_%s.mat', circuito)), 'file')
            delete(fullfile(datosFolder, sprintf('circuit_%s.mat', circuito)));
        end
        rethrow(ME);
end