<?php

/**
 * Orígenes CORS de los frontends INAMAP publicados por el túnel de desarrollo
 * (inamap-frontend-domain: pnpm dev:tunnel:all). Inocuo en modo local.
 */
return [
    'allowed_origins' => [
        'https://app-dev.inamap.space',
        'https://web-dev.inamap.space',
        'https://system-dev.inamap.space',
    ],
];
