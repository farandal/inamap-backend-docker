<?php

/**
 * Orígenes CORS de los servidores de desarrollo del frontend INAMAP
 * (inamap-frontend-domain), anexados a config('cors.*') del core.
 *
 *   5180 inamap-app · 5181 inamap-web · 5182 inamap-system
 *
 * Agregar aquí los dominios de staging/producción cuando se definan (S6).
 */
$ports = [5180, 5181, 5182];

return [
    'allowed_origins' => [
        ...array_map(fn ($p) => "http://localhost:{$p}", $ports),
        ...array_map(fn ($p) => "http://127.0.0.1:{$p}", $ports),
    ],
];
