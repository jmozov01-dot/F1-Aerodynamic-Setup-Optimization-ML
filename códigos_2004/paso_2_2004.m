%% PASO 2: Extracción de tiempos de vuelta
clear; clc;

% Seleccionar carpeta con CSVs
folder = uigetdir(pwd, 'Seleccionar carpeta con archivos de telemetría');
if folder == 0
    disp('Cancelado');
    return;
end

% Detectar circuito con el nombre de la carpeta
[~, foldername] = fileparts(folder);
parts = strsplit(lower(foldername), ' ');
circuito = parts{end};
if contains(circuito, 'telemetria')
    circuito = parts{1};
end

fprintf('\nCircuito: %s\n', circuito);

% Buscar archivos
files = dir(fullfile(folder, '*.csv'));
fprintf('Archivos: %d\n\n', length(files));

% Variables acumuladoras
all_laps = [];
lap_mapping = [];  % Para sincronizar con PASO 3
lap_id = 0;

%% Procesar cada archivo
for f = 1:length(files)
    filename = fullfile(files(f).folder, files(f).name);
    
    try
        % Leer setup (fila 17)
        fid = fopen(filename, 'r');
        for i = 1:17
            line = fgetl(fid);
        end
        fclose(fid);
        
        setup = strsplit(line, ';', 'CollapseDelimiters', false);
        fw = str2double(setup{6});  % Alerón delantero
        rw = str2double(setup{7});  % Alerón trasero
        hf = str2double(setup{4});  % Altura delantera
        hr = str2double(setup{5});  % Altura trasera
        
        % Leer telemetría
        data = readtable(filename, 'Delimiter', ';', 'HeaderLines', 21);
        lap_times = data.Var86;
        
        % Filtrar tiempos de vuelta
        valid = ~isnan(lap_times);
        lap_times = lap_times(valid);
            
        % Detectar cambio de vuelta cuando el tiempo baja más de 10 segundos de golpe
        lap_change = find(diff(lap_times) < -10);
        
        % Si dos cambios están a menos de 300 muestras se ignora el segundo, evita errores
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

        % Filtrar vueltas válidas 
        vueltas = vueltas(vueltas(:,1) >= 0 & vueltas(:,2) > 60 & vueltas(:,2) < 100, :);
        
        % Acumular
        for i = 1:size(vueltas, 1)
            lap_id = lap_id + 1;
            all_laps = [all_laps; lap_id, vueltas(i,2), f, fw, rw, hf, hr];
            lap_mapping = [lap_mapping; f, vueltas(i,1), lap_id];  
        end
        
        % Mostrar datos
          fprintf('Archivo %d: FW=%d RW=%d HF=%d HR=%d - %d vueltas\n', f, fw, rw, hf, hr, size(vueltas,1));
        if ~isempty(vueltas)
            fprintf('Min: %.3f s, Max: %.3f s, Media: %.3f s\n', min(vueltas(:,2)), max(vueltas(:,2)), mean(vueltas(:,2)));
        end
        fprintf('\n');  
        
    catch
        fprintf('Archivo %d: error\n\n', f);
    end
end

%% Guardar
laps.lap_data = all_laps;
laps.mapping = lap_mapping;

save_file = fullfile('datos_2004', sprintf('laps_%s.mat', circuito));
save(save_file, 'laps');

%% Resumen
fprintf('\nTotal: %d vueltas\n', size(all_laps,1));
fprintf('Guardado: %s\n', save_file);