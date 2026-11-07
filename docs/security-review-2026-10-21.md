# Revisión de seguridad — 21 de octubre de 2026

Revisión focalizada del código de la app iOS, el dashboard local y sus conexiones,
realizada durante el rediseño. Es una revisión de alcance limitado, no una
certificación, una auditoría independiente ni una prueba de ausencia de fallas.

## Hallazgos corregidos en el backend

### Alta: normalización remota de resultados de laboratorio sin una elección explícita

Antes, `parse_pdf` llamaba automáticamente a un normalizador remoto cuando extraía
menos de cuatro marcadores y existía `AGENT_BACKEND_API_KEY`. Enviaba hasta 120
líneas con nombres de análisis, valores, unidades y rangos a
`https://agent-backend.thomas.md/v1`. La interfaz afirmaba que los resultados nunca
salían del equipo. Además, la primera lectura de `/api/blood/report` importaba
automáticamente los PDF de la carpeta configurada, de modo que abrir esa pantalla
podía alcanzar esa ruta sin pulsar Importar.

Corrección: se eliminó la llamada remota y sus funciones auxiliares de
[`blood.rs`](../crates/oura-cli/src/blood.rs). Un reporte no reconocido conserva
el estado `partial` y sus advertencias. La lectura del reporte abre únicamente una
base existente en modo de solo lectura; no crea la base ni importa documentos.
La importación permanece disponible mediante la acción explícita correspondiente.

Verificación: búsqueda de clientes HTTP y endpoints en el código de ejecución;
pruebas de parsers conocidos y regresión
`report_read_does_not_create_store_or_import_pending_files`. No se envió ningún
documento real al servicio eliminado durante esta revisión.

### Alta: el cuerpo de un formulario podía satisfacer la protección CSRF

`header(req, name)` recorría todas las líneas de la solicitud, incluidas las del
cuerpo. Un formulario `text/plain` podía colocar `X-Oura-Dash:=1` en el cuerpo y
satisfacer la comprobación de presencia de encabezado. Las acciones sin cuerpo
JSON, como sincronizar e importar una carpeta, podían ejecutarse desde una página
externa. El visualizador de movimiento tenía el mismo patrón para `X-Oura-Viz`.

Corrección en [`dashboard.rs`](../crates/oura-cli/src/dashboard.rs) y
[`motion_server.rs`](../crates/oura-cli/src/motion_server.rs): la lectura de
encabezados termina en la primera línea vacía, omite la línea de solicitud y exige
el valor `1` para el encabezado propio. El dashboard también rechaza un `Origin`
ajeno cuando está presente; el visualizador ya tenía esa comprobación. Se mantiene
el servidor limitado a `127.0.0.1` y la validación de `Host`.

Regresión segura, sin iniciar Bluetooth ni importar archivos:

```http
POST /api/sync HTTP/1.1
Host: localhost:8090
Content-Type: text/plain

X-Oura-Dash:=1
```

El buscador de encabezados debe devolver `None` para `x-oura-dash` y rechazar la
acción. Las pruebas incluyen el equivalente del visualizador, un `Host` falso en
el cuerpo, encabezados válidos y un origen externo.

También se añadieron `X-Frame-Options: DENY`, una política `frame-ancestors 'none'`
y `nosniff` a las respuestas del dashboard para reducir el riesgo de que una web
externa enmarque la interfaz y provoque clics engañosos.

## Hallazgos nativos corregidos y verificación de distribución

- **Alta, empaquetado de datos personales — corregido en la configuración:** la configuración original de
  [`project.yml`](../apps/ios/OuraApp/project.yml) incluía `../../../oura.db` en
  los recursos de la app para dispositivo. Una compilación con una base real podía
  distribuirla dentro del IPA. La configuración CI no la incluía. Se retiró ese
  recurso del proyecto de dispositivo; aún debe verificarse el contenido final del IPA. Los
  scripts locales `build_run.sh` y `build_run_torch.sh` solo incluyen una base personal
  si se configura explícitamente `HEALTH_INCLUDE_PERSONAL_DATA=1`; ese artefacto de
  desarrollo no debe distribuirse.
- **Media, restauración no transaccional — corregida:** la implementación original de
  `SyncView.restore` en [`OuraApp.swift`](../apps/ios/OuraApp/OuraApp.swift)
  borraba la base operativa antes de copiar el reemplazo y no adquiría el mismo
  `WorkGate` que sincronización/análisis. Un fallo de copia o una operación que
  arrancase durante el selector podía dejar el estado incompleto. Ahora el flujo
  adquiere `WorkGate` y llama a
  [`DatabaseRestore.swift`](../apps/ios/OuraApp/DatabaseRestore.swift): abre el
  candidato en solo lectura, valida integridad y las cuatro tablas esperadas,
  rechaza vistas/triggers y usa la API de backup de SQLite para reemplazar el
  contenido mediante una transacción. No borra antes la base ni sus archivos WAL.
  Un candidato inválido se rechaza antes de abrir el destino; un backup fallido
  revierte la operación. Se validaron preservación ante esquema incorrecto,
  candidato inexistente sin creación de archivos, contenido confirmado en WAL y
  bloqueo del destino con preservación de los datos previos.
- **Media, persistencia de la clave — corregida en código:** `Keychain.saveKey` en
  [`RingSync.swift`](../apps/ios/OuraApp/RingSync.swift) eliminaba primero el elemento
  y luego ejecutaba `SecItemAdd`, sin comprobar los códigos de retorno. Ahora usa
  `SecItemUpdate`, añade solo cuando no existe y propaga un error si falla. La
  política es `WhenUnlockedThisDeviceOnly`; la sincronización se pausa cuando los
  datos protegidos no están disponibles. La persistencia real debe comprobarse en
  dispositivo.

Estos puntos describen el problema original y su corrección en el código revisado;
la auditoría de publicación debe comprobar la versión y el IPA concretos.

## Inventario de conexiones y salidas de datos

| Ruta | Activación | Información que cruza el límite |
| --- | --- | --- |
| iOS ↔ anillo, CoreBluetooth | Módulo Oura activado explícitamente; emparejamiento/sincronización y reanudación con controles en los puntos BLE | Protocolo BLE, autenticación y mediciones del dispositivo |
| Navegador ↔ `127.0.0.1:puerto` | Apertura y acciones del dashboard | Resumen de salud, perfil, laboratorio, genética y herramientas de clave, dentro del equipo |
| CLI → `https://ftp.ebi.ac.uk/pub/databases/spot/pgs/scores/...` | Acción explícita de descargar una definición PGS | ID público seleccionado y metadatos de conexión; no se incluye el genoma en esa petición. Ver `dna.rs::fetch` y `download` |
| Enlaces a `www.pgscatalog.org` | Clic explícito | Navegación al catálogo público según las reglas del navegador |
| iOS → Apple Health | Opción desactivada por defecto; exige autorización HealthKit | Muestras derivadas de salud. Su copia/sincronización posterior depende de ajustes del sistema ajenos a esta app |
| Compartir/exportar JSON, base o diagnósticos | Acción explícita del usuario | Archivo elegido, datos de salud y, en ciertos reportes, perfil/zona horaria. El destino lo controla la hoja de compartir |
| Herramientas de desarrollo → GitHub/crates.io/PyTorch/Oura | Compilación o ejecución manual de scripts | Dependencias públicas; las herramientas de firmware/token son utilidades separadas de investigación, no conexiones automáticas de la interfaz |

Tras retirar el normalizador, no se encontraron otros clientes HTTP en los Swift
de la app ni otros envíos de resultados de laboratorio en el backend revisado.
Esta conclusión proviene de inspección de código; no equivale a una captura de
tráfico de una app instalada ni cubre comportamiento desconocido de dependencias.

## Límites y seguimiento

El encabezado propio protege frente a solicitudes de páginas externas; no es una
credencial contra otros procesos del mismo equipo. Un proceso local puede enviar
sus propios `Host` y encabezados al servidor y, entre otras acciones, solicitar la
clave mediante `/api/ring-key`. El modelo actual confía en el usuario/sesión del
equipo. No debe exponerse el puerto a una red ni publicarse mediante un proxy sin
autenticación adecuada.

La base, los caches y diagnósticos iOS están en Application Support. No se observó
una política explícita de exclusión de copias de seguridad o protección de archivos
en esos puntos. iOS aporta su protección del sistema; no se debe confundir esto
con cifrado propio de la base ni prometer que un dato nunca podrá entrar en una
copia del sistema. Los archivos temporales exportados también requieren una
política de limpieza y una explicación de su contenido.

Importar un manifiesto declarativo de módulo no crea aislamiento para código de
terceros. Una futura carga de código requiere revisar permisos efectivos,
aislamiento, firmas/procedencia, actualización, persistencia y revocación. Un
permiso mostrado en la interfaz no demuestra que el sistema lo haga cumplir.

No se realizaron pruebas en un anillo físico, revisión criptográfica del protocolo,
análisis de firmware, auditoría de todos los modelos ni revisión completa de la
cadena de dependencias. Tampoco se revisaron todos los posibles flujos DOM del
dashboard. El servidor HTTP artesanal todavía necesita una revisión específica de
límites, fragmentación de solicitudes y disponibilidad.

## Comprobaciones ejecutadas

- `cargo test -p oura-cli --no-default-features`: 13 pruebas aprobadas, incluidas
  cuatro regresiones añadidas para las correcciones anteriores. La prueba del PDF
  personal y la de la carpeta genética se omiten internamente cuando sus archivos
  opcionales no existen; su resultado no demuestra que esos archivos se probaron.
- `rustfmt --edition 2021 --check` en los tres Rust modificados: aprobado.
- `git diff --check` en los tres Rust modificados: aprobado.
- `swiftc` en macOS: comprobación de tipos de `DatabaseRestore.swift` aprobada;
  cuatro escenarios de `DatabaseRestoreTests.swift` ejecutados en un harness local
  con aserciones equivalentes, aprobados. No equivale a una ejecución XCTest en un
  simulador iOS.
- Compilación y enlace de la app iOS sin Torch para `arm64-apple-ios17.0-simulator`:
  aprobados. No hay runtimes de simulador instalados, por lo que no se ejecutó la app
  iOS ni se capturó su interfaz. La variante con Torch requiere recursos locales.
- Siete pruebas de manifiestos/módulos en un harness macOS con el código exacto:
  aprobadas. No equivale a toda la suite de la app ejecutada en iOS.
- Validación web en navegador: temas persistentes, activación/importación de módulos,
  validaciones de manifiestos, informes, exportación y tamaños de 320 a 1440 px.
  Las capturas de diseño usan un resumen vacío interceptado para no añadir mediciones
  ficticias al producto. También se probaron informes con una fixture de QA temporal.
- Búsqueda de clientes HTTP, endpoints, almacenamiento de claves, exportaciones y
  recursos de empaquetado: completada dentro de las rutas indicadas.

Para una auditoría periódica, registrar el commit/artefacto revisado, dependencias,
hallazgos pendientes, pruebas y captura de tráfico de una compilación real.

## Revisión posterior de interfaz (v2)

La navegación Inicio/Anillo/Ajustes conserva el bloqueo explícito del módulo y las
validaciones de manifiestos. La imagen del anillo se incluye como PNG local tanto
en el servidor Rust como en la app; no añade peticiones a servicios de imágenes.
Se comprobaron de nuevo activación/importación, perfil, temas persistentes,
informes/exportación y tamaños de 320 a 1440 px sin errores JavaScript ni conexiones
externas en la prueba de navegador. El servidor real también se abrió con una
base desechable: las opciones del anillo siguen accesibles sin historial, y los
errores de carga conservan sus detalles técnicos en un apartado desplegable.
