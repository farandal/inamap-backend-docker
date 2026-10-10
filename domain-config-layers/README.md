# Capas de configuración (opcional)

Cada subcarpeta (p. ej. `10-cors/`) contiene archivos `*.php` con la misma forma que
`domain/config/*.php`. Se aplican en orden alfabético **antes** de la config del dominio,
que siempre tiene la última palabra. Vacío por defecto.

Ejemplo — orígenes CORS extra para el visor (`10-cors/cors.php`):

```php
<?php
return [
    'allowed_origins' => ['https://app.inamap.example'],
];
```
