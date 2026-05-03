%% PASO 1: Carga de datos del circuito (OpenTRACK)
clear; clc;
fprintf('\nPASO 1: Carga de circuito OpenTRACK\n\n');

%% Selección de archivo
[file, path] = uigetfile('*.mat', 'Seleccionar archivo de circuito OpenTRACK');
if file == 0
    fprintf('Cancelado\n');
    return;
end

%% Extracción del nombre del circuito
% Formato esperado: "OpenTRACK_NombreCircuito_.mat"
[~, filename, ~] = fileparts(file);
parts = strsplit(filename, '_');
if length(parts) >= 2
    circuito = lower(parts{2});
else
    circuito = lower(filename);
end

fprintf('Circuito identificado: %s\n', circuito);

%% Carga de datos
matdata = load(fullfile(path, file));

% Extracción de variables principales
X = matdata.X;                     % Coordenada X (m)
Y = matdata.Y;                     % Coordenada Y (m)
Z = matdata.Z;                     % Coordenada Z (m)
r = matdata.r;                     % Curvatura (m^-1)
bank = matdata.bank;               % Peralte (º)
incl = matdata.incl;               % Inclinación (º)
factor_grip = matdata.factor_grip; % Factor de agarre 
dx = matdata.dx;                   % Diferencial de distancia (m)

% Cálculo de distancia acumulada
distance = cumsum(dx);
distance = [0; distance(1:end-1)];

% Información del circuito
info = matdata.info;
nombre_completo = info.name;
pais = info.country;
n_points = matdata.n;
longitud = distance(end);

%% Resumen de datos cargados
fprintf('\n Resumen del circuito: \n');
fprintf('Nombre: %s, %s\n', nombre_completo, pais);
fprintf('Longitud: %.0f m\n', longitud);
fprintf('\nDatos disponibles:\n');
fprintf('  - Coordenadas 3D (X, Y, Z)\n');
fprintf('  - Curvatura (r): [%.6f, %.6f]\n', min(r), max(r));
fprintf('  - Peralte (bank): [%.1f, %.1f] grados\n', min(bank), max(bank));
fprintf('  - Inclinación (incl): [%.1f, %.1f] grados\n', min(incl), max(incl));
fprintf('  - Factor de agarre: [%.2f, %.2f]\n', min(factor_grip), max(factor_grip));

%% Guardado de datos procesados
if ~exist('datos_2004', 'dir')
    mkdir('datos_2004');
end

save_file = fullfile('datos_2004', sprintf('circuit_%s.mat', circuito));

circuit_data.name = nombre_completo;
circuit_data.country = pais;
circuit_data.distance = longitud;
circuit_data.n_points = n_points;
circuit_data.X = X;
circuit_data.Y = Y;
circuit_data.Z = Z;
circuit_data.distance_array = distance;
circuit_data.curvature = r;
circuit_data.bank = bank;
circuit_data.incline = incl;
circuit_data.grip_factor = factor_grip;
circuit_data.dx = dx;

save(save_file, 'circuit_data');

fprintf('\nDatos guardados en: %s\n', save_file);