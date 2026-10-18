<h1 align="center">
  <br>
  <a href="https://github.com/fparrav/facekey"><img src="facekey/Assets.xcassets/appicon.imageset/appicon.png" alt="Facekey" width="150"></a>
  <br>
  Facekey
  <br>
</h1>

<h3 align="center">Desbloqueo facial para tu Mac</h3>

<p align="center"><a href="README.md">🇺🇸 English</a> | <b>🇪🇸 Español</b></p>

<p align="center"><sub>Un fork de <a href="https://github.com/jonnyoo/glance">jonnyoo/glance</a>, desarrollado a su propio ritmo.</sub></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-black.svg" alt="Swift">
</p>

Facekey lleva la experiencia de FaceID de tu iPhone a la Mac que tienes frente a ti. Desbloquea tu Mac con solo mirarla: sin escribir nada y sin buscar la llave de Touch ID. Todo se ejecuta en el dispositivo con los frameworks Vision y Core ML de Apple, así que los datos de tu rostro y la contraseña de tu Mac nunca pasan por internet. La interfaz vive en el notch de tu MacBook, con animaciones fluidas al estilo de la Dynamic Island.

> [!NOTE]
> **Este es un fork personal.** Facekey existe para que yo pueda seguir mi propio ritmo de desarrollo y agregar las funciones que me gustaría que glance tuviera. No reemplaza al original, no sigue los cambios de upstream con un calendario fijo, y solo incorporo los cambios de upstream cuando quiero. Todo lo que funciona aquí partió del trabajo de [Jonathan Zhou](https://github.com/jonnyoo). Consulta [Cómo se diferencia este fork de glance](#cómo-se-diferencia-este-fork-de-glance) para ver qué agregué o cambié.


https://github.com/user-attachments/assets/77438826-80a9-4ab2-9fc3-42407a2d0adb


---

> [!WARNING]
> ## Lee esto antes de descargar
> ## Facekey no es tan seguro como FaceID o Touch ID de Apple
> 
> Las MacBook no traen los sensores de profundidad que hacen que FaceID sea confiable y seguro en un
> iPhone. Un iPhone construye un mapa 3D de tu rostro; la cámara web de una MacBook ve una imagen plana en 2D. Esto significa que:
> 
> - Facekey derrota, con una confianza razonable, una foto impresa y una foto en la pantalla de un teléfono (la detección de vida estricta debe estar activada)
> - Facekey no derrota de forma confiable un video tuyo
> - macOS no tiene ninguna API que permita a una app de terceros autorizar un inicio de sesión, así que Facekey desbloquea escribiendo
>   tu contraseña guardada en la pantalla de bloqueo
> 
> Facekey es una comodidad, no una mejora de seguridad. Continúa solo si aceptas ese compromiso.

## Instalación

**Requisitos:**
- macOS 15 Sequoia o posterior
- Mac con Apple Silicon o Intel

<a href="https://github.com/fparrav/facekey/releases/latest/download/Facekey.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/cdb8af97-1ee2-4669-b7cb-dcfb56c9dd61" alt="Download for Mac" /></a>

Abre el archivo `.dmg` y arrastra Facekey a `/Applications`; luego ábrelo.


## Permisos

| Permiso | Para qué |
|---|---|
| **Cámara** | Para ver tu rostro. Los fotogramas se procesan en memoria y nunca se escriben en el disco. |
| **Accesibilidad** | Para escribir tu contraseña en la pantalla de bloqueo. |
| **Touch ID** | Protege la clave que cifra los datos de tu rostro y tu contraseña. |

## Cómo funciona

1. Abre la app y sigue la introducción para registrar tu rostro. Facekey te guía para capturarlo mientras giras la cabeza hacia nueve
   direcciones. Cada fotograma se convierte en un *embedding* de 512 números, una huella matemática, y la
   imagen se descarta.
2. Ingresa una vez la contraseña de tu Mac, cifrada detrás de Touch ID.
3. Cuando tu Mac se bloquea o despierta del reposo, la animación aparece en el notch y empieza a buscar un rostro.
4. Si eres tú, y las comprobaciones de detección de vida confirman que eres una persona real, Facekey escribe la
   contraseña y entras.

## Funciones

| Función | Descripción |
|---|---|
| **Desbloqueo facial** | Se activa al despertar, al bloquear o al presionar espacio en la pantalla de bloqueo. Elige cualquier combinación. |
| **Varias identidades** | Registra a varias personas, o varias versiones de ti mismo: con lentes, con barba, con distinta iluminación. Desactiva cualquiera sin borrarla. |
| **Comprobaciones de detección de vida** | Observa el movimiento y los reflejos que distinguen un rostro real de una foto. Nivel *Ligero* o *Estricto*, o desactivada. |
| **Interfaz en el notch** | Una píldora cerrada que se expande en una animación de escaneo con estados de éxito y de fallo. Pasa el cursor para reintentar, o desactiva las animaciones por completo y Facekey permanece invisible. |
| **Color de acento** | Elige verde, lima, menta, azul o ámbar en Ajustes → App. El notch, las animaciones de escaneo, la píldora, la barra lateral y los botones lo siguen, y el ícono verde de la app es el predeterminado. |
| **Texto de estado en el notch** | Una línea breve bajo el escaneo dice qué ocurre: buscando tu rostro, desbloqueada, rostro no reconocido, cámara no disponible o aprobando `sudo`. Una marca animada pequeña antecede al texto: un arco que gira mientras trabaja, un anillo que se cierra en un check o una cruz, una alerta ámbar suave. No aparece cuando las animaciones están desactivadas. |
| **Cámara y pantalla** | Elige qué cámara usar, incluidas cámaras distintas para la pantalla integrada y para un monitor externo. |
| **Sesiones con bloqueo automático** | La sesión de Touch ID se vuelve a bloquear sola tras el periodo de inactividad que elijas, para que una Mac sin atender no quede autorizada para siempre. |
| **Verificar tras otros desbloqueos** | Opcional, desactivada por defecto. Después de que algo distinto de Facekey desbloquee la Mac, como un Apple Watch, un escaneo breve comprueba quién está frente a la pantalla y la vuelve a bloquear si ve un rostro que no está registrado. Se ejecuta después del desbloqueo, así que no puede impedir el desbloqueo con el Apple Watch, y una habitación vacía deja la Mac desbloqueada. |
| **Aprobación de sudo** | Opcional, desactivada por defecto. Cuando `sudo` pide una contraseña en una terminal, Facekey muestra en el notch una superposición con Aceptar / Cancelar, verifica tu rostro y lo aprueba, según la configuración de pantallas y según la app. Es más débil que Touch ID, así que lee antes [Aprobación de sudo](#aprobación-de-sudo). |
| **Respuesta háptica del trackpad** | Pasar el cursor sobre el notch activa la respuesta háptica |
| **Compatibilidad con Mac sin notch** | En las Mac sin notch se reemplaza por un diseño en forma de píldora, al estilo de la Dynamic Island. |
| **Tus datos, tu decisión** | Edita o elimina tu registro o tu contraseña guardada en cualquier momento. Los archivos cifrados se eliminan de inmediato. |

## Cómo se diferencia este fork de glance

Glance es una app pulida y enfocada. Este fork conserva su idea, su arquitectura y la mayor parte de su código, y agrega lo que quise para mi uso diario. Todo lo que no aparece aquí se comporta como en el original.

### Agregado

| Adición | Qué hace |
|---|---|
| **Verificar tras otros desbloqueos** | Opcional, desactivada por defecto. Después de un desbloqueo con Apple Watch, Touch ID o una contraseña escrita, un escaneo breve comprueba quién está frente a la pantalla y vuelve a bloquear la Mac si un rostro no reconocido permanece a la vista durante 2 segundos. Consulta [Desbloqueos por otros métodos](#desbloqueos-por-otros-métodos). |
| **Aprobación de sudo** | Opcional, desactivada por defecto. Un módulo PAM colocado antes de Touch ID en `sudo_local` le pide a Facekey que apruebe `sudo` con una superposición en el notch y un escaneo del rostro, con una lista de apps permitidas y bloqueadas y un historial de auditoría. Consulta [Aprobación de sudo](#aprobación-de-sudo). |
| **Identidad de Facekey** | Un ícono de la app y una marca de la barra de menús nuevos, un color de acento que puedes cambiar y una marca vectorial usada en Acerca de y en la introducción. |
| **Texto de estado en el notch** | Una línea bajo el escaneo para cada estado, incluido un *Cámara no disponible* en ámbar cuando no se puede abrir la cámara en la pantalla de bloqueo. La línea de fallo menciona pasar el cursor para reintentar solo cuando esa opción está activada. |
| **Distancia de detección calibrada** | La distancia de detección es un control deslizante de seis posiciones que se guarda por separado para cada configuración de pantallas (integrada, integrada + externa, externa), y una hoja guiada de **Calibrar** mide el ancho de tu rostro con la cámara de esa configuración. |
| **Comportamiento por configuración de pantallas** | El desbloqueo facial se puede activar o desactivar para *Solo integrada*, *Integrada + externa* y *Solo externa*, cada una con su propia cámara. El desbloqueo se vuelve a comprobar cuando cambian las pantallas con la Mac bloqueada, y recurre a la pantalla del notch si el ID de una pantalla externa fijada queda obsoleto tras el reposo. |
| **Desbloquear la sesión al iniciar** | Opcional. Facekey desbloquea su propia sesión al arrancar, sin pedir Touch ID. Esto cambia la protección de Touch ID sobre la contraseña guardada por comodidad. Déjala desactivada si no quieres eso. |
| **Página de permisos** | Ajustes muestra si Accesibilidad y Cámara siguen concedidos, explica qué deja de funcionar sin cada uno y abre el panel correcto de Ajustes del Sistema. Volver a firmar la app puede quitar Accesibilidad sin avisar, y esto lo hace visible. |
| **Pausa del escaneo al despertar** | Cuando un escaneo iniciado por una señal de despertar no encuentra a nadie, las siguientes señales de despertar no vuelven a encender la cámara durante 10 minutos. Bloquear de nuevo, desbloquear, pasar el cursor sobre el notch o presionar espacio termina la pausa. |
| **Control para salir en la introducción** | El flujo de primer uso muestra un botón de cierre en cada paso excepto en el registro y en la finalización, para que puedas salir sin un atajo oculto. |
| **Diagnóstico de escaneos** | Cada escaneo registra qué lo activó, el ancho del rostro, la similitud y las lecturas de detección de vida, y los registros se conservan; así se encontraron la mayoría de las correcciones que siguen. |
| **Autopruebas sin conexión** | `tools/` incorpora autopruebas independientes para la lógica de verificación y la calibración de distancia, además de una sonda que comprueba que el atajo de re-bloqueo funciona en tu versión de macOS. |

### Cambiado

| Cambio | Qué hace |
|---|---|
| **Reconocimiento más estable** | Un escaneo compara un promedio móvil de los fotogramas recientes en lugar de uno solo, omite los primeros fotogramas oscuros de la cámara y necesita unos cuantos fotogramas consistentes antes de decidir. Además, cada fotograma debe superar por sí mismo un mínimo, de modo que una persona ajena que se pone delante no pueda apoyarse en el promedio de los fotogramas anteriores del dueño. La ventana de escaneo por defecto es más larga, y una falta de coincidencia sostenida tarda más en rendirse. |
| **Agregar capturas, no volver a capturar** | Agregar capturas a una identidad las añade en lugar de descartar las anteriores. El límite de muestras por identidad es 72, y las de menor calidad se descartan primero. El paso final indica cuántas se conservaron. |
| **Poses de registro más fáciles** | Las poses diagonales superiores de la cabeza eran difíciles de lograr, así que los umbrales de giro y de inclinación son más permisivos, y las poses estancadas amplían su tolerancia antes. |
| **Falsos rechazos de detección de vida** | La señal de reflejo ya no se activa con un rostro real sobreexpuesto, y un borde del fondo que recorta el cuadro del rostro ya no activa la señal de dispositivo. Por lo demás, la detección de fotos y pantallas funciona como antes. |
| **Ajustes en cinco páginas** | La barra de pestañas ahora es una barra lateral con Resumen, Acceso, Seguridad, Cámara y pantallas, y App. Resumen muestra una lista de *lista para desbloquear* y enlaza cada paso pendiente con su página. Todas las filas anteriores siguen ahí, reagrupadas. |

### Renombrado y reapuntado

- La app, el proyecto, los identificadores de paquete y el servicio de Llavero son `Facekey` y `com.fparrav.facekey`.
- En el primer inicio, Facekey copia tus elementos del Llavero de glance, el almacén de rostros y las preferencias, así que no hay que registrar nada de nuevo.
- Se eliminan el feed de actualizaciones de Sparkle y la clave de firma de upstream, y los controles de actualización permanecen ocultos hasta que este fork tenga su propio feed. Los enlaces de descarga y de comentarios apuntan a este repositorio.
- El equipo de firma vive en un `Local.xcconfig` sin seguimiento, así que nunca llega a un commit.

### Sin cambios

El modelo de reconocimiento (ArcFace a través de Core ML), las señales de detección de vida, el almacenamiento cifrado de los datos del rostro y la contraseña, la forma en que se escribe la contraseña en la pantalla de bloqueo y la interfaz del notch provienen de glance.

---

# Privacidad y seguridad

Facekey está diseñado para mantener los datos biométricos y las credenciales en el dispositivo.

### Datos del rostro

Facekey nunca guarda imágenes de la cámara. Durante el registro, cada rostro capturado se convierte en un **embedding de 512 dimensiones** mediante un modelo de Core ML basado en ArcFace. Luego el fotograma original se descarta.

Los embeddings se guardan localmente y se cifran con **AES-GCM**.

### Credenciales

La contraseña de tu Mac se guarda como datos cifrados y nunca se escribe en el disco en texto plano. La clave de cifrado es una **clave AES de 256 bits guardada en el Llavero de macOS**, protegida con `userPresence`, lo que exige Touch ID o la contraseña de tu dispositivo.

La clave solo se mantiene en memoria mientras hay una sesión de Facekey autorizada.

### Flujo de desbloqueo

Facekey no escribirá tu contraseña solo porque un rostro coincida. Un desbloqueo requiere todo lo siguiente:

1. Hay una sesión de Facekey autorizada y válida.
2. La Mac está realmente en la pantalla de bloqueo.
3. Una identidad habilitada coincide por encima del umbral de similitud configurado.
4. Las comprobaciones de detección de vida aceptan el rostro detectado.
5. Hay permiso de Accesibilidad disponible para ingresar la contraseña.

El reconocimiento facial y la detección de vida se ejecutan de forma independiente y ambos deben tener éxito antes de que se ingrese la contraseña. 

### Desbloqueos por otros métodos

macOS no permite que una app apruebe o bloquee un desbloqueo hecho con un Apple Watch, Touch ID o una contraseña escrita, así que Facekey no puede controlarlos. Con *Verificar mi rostro tras otros métodos de desbloqueo* activado (Ajustes → Seguridad), Facekey mira la pantalla hasta 6 segundos después de un desbloqueo así. Una coincidencia con cualquier identidad habilitada termina la comprobación sin avisar. Un rostro no reconocido que permanece a la vista durante 2 segundos vuelve a bloquear la pantalla. Si no hay nadie a la vista, no ocurre nada. Tras un re-bloqueo, la comprobación se pausa durante 2 minutos para que no pueda dejarte fuera en un ciclo. Es una red de seguridad posterior, no una barrera.

### Aprobación de sudo

Opcional, desactivada por defecto, y se instala desde **Ajustes → Seguridad**, que pide tu contraseña de administrador. Un módulo PAM pequeño, `pam_facekey.so`, se coloca antes de `pam_tid.so` en `/etc/pam.d/sudo_local`. Cuando `sudo` pide una contraseña en una terminal, el módulo le pregunta a Facekey. Facekey muestra en el notch una superposición con **Aceptar** y **Cancelar**, y aprueba solo después de que aceptes y de que tu rostro coincida. Cualquier otro resultado (Cancelar, un tiempo agotado, una app bloqueada, una sesión bloqueada, Facekey sin ejecutarse, ninguna terminal) pasa al aviso normal de `sudo`, así que esto solo agrega una vía de acceso en los casos que actives y nunca quita una.

**Requisitos**

- macOS 15 o posterior, con Facekey en ejecución, al menos un rostro registrado y el permiso de Cámara.
- Una sesión de Facekey desbloqueada. Con la sesión bloqueada, las solicitudes pasan al aviso normal.
- Una compilación de Facekey firmada con un equipo de desarrollador. El módulo se compila con el ID de ese equipo y ignora toda solicitud si no lo tiene, así que una compilación con firma ad hoc no puede usar esta función.
- Tu contraseña de administrador, una sola vez, para instalarla o quitarla. No necesita ningún permiso adicional, como Acceso total al disco o Accesibilidad.
- `sudo` ejecutado por ti en una terminal. Nunca actúa para root, por SSH, ni cuando un programa entrega la contraseña con `sudo -S` o `-A`.
- La función activada para tu configuración de pantallas actual en Ajustes → Seguridad.

**Riesgos**

- **Es más débil que Touch ID.** Una coincidencia de rostro es una prueba más blanda que una huella, y la cámara de un MacBook ve una imagen plana (consulta la advertencia al inicio). Quien logre pasar la verificación del rostro y pulsar Aceptar obtiene root mediante `sudo`.
- **Es una puerta a root.** La superposición solo responde a un clic de hardware, así que un script que envíe un clic cuenta como Cancelar, pero alguien frente a tu Mac desbloqueada aún puede usarla.
- **Cambia un archivo del sistema y carga código en `sudo`.** `pam_facekey.so` se ejecuta como root dentro de cada `sudo`, y el instalador edita `/etc/pam.d/sudo_local`. El módulo solo confía en un Facekey firmado por el mismo equipo y falla en abierto: ante cualquier error no hace nada y `sudo` pide su contraseña. El instalador copia sus archivos a una carpeta privada y verifica la firma antes de ejecutarlos como root, pero un proceso de tu propio usuario aún podría intentar reemplazarlos en esa breve ventana.
- **Una actualización de macOS puede eliminar la entrada.** Entonces `sudo` vuelve a Touch ID o a la contraseña, y Ajustes → Seguridad ofrece repararla.
- **El historial puede contener secretos.** Los comandos se guardan con sus argumentos, salvo que actives *Guardar solo el nombre del programa*. El archivo está cifrado con una clave de tu Llavero.

**Lo que debes saber antes de activarla**

- **Las apps están en una lista.** La primera vez que una app lo solicita, Facekey pregunta si debe permitirla, y la reconoce por su firma de código (o, si no está firmada, por su código). Una app bloqueada se rechaza de inmediato. La lista está en Ajustes → Seguridad.
- **La superposición siempre es visible.** No hay aprobación silenciosa, y el módulo solo habla con un Facekey firmado por el mismo equipo.
- **Hay un historial de auditoría.** Ajustes → Seguridad muestra cuándo ocurrió cada solicitud, qué app la hizo, el comando y cómo terminó. Está cifrado y se puede borrar, y *Guardar solo el nombre del programa* deja fuera los argumentos.
- **Según la configuración de pantallas.** Se puede activar o desactivar para pantalla *Integrada*, *Integrada + externa* y *Externa*.
- **Se puede quitar.** Quitar deja `sudo_local` exactamente como estaba. Una actualización de macOS puede eliminar la entrada, y entonces Ajustes ofrece repararla.

### Local por diseño

El reconocimiento facial, el registro del rostro y la detección de vida se ejecutan por completo en el dispositivo con Vision y Core ML. Facekey no envía datos del rostro, fotogramas de la cámara ni credenciales a ningún servidor.


### Cómo distingue un rostro de una foto

Cinco señales independientes sobre una ventana móvil de unos 2 s, con dos funciones:

- Las **señales de rechazo** son evidencia de una suplantación: un reflejo de pantalla, o un rectángulo con forma de dispositivo que enmarca el
rostro. Cualquiera de las dos hace fallar el escaneo de inmediato y prevalece sobre todo lo demás.
- Las **señales de confirmación** son evidencia de un rostro real: la geometría de puntos de referencia plano frente a 3D, el paralaje de la nariz
al girar la cabeza y los parpadeos. Basta con una, y su ausencia nunca es un fallo, ya que una
persona real puede quedarse quieta y no parpadear.

La detección ligera solo incluye señales de rechazo. La detección estricta incluye tanto las de rechazo como las de confirmación.

### Face Lab

Face Lab es una consola de depuración oculta para probar el reconocimiento facial y la detección de vida con valores reales.

**Para abrirla:** Ajustes → App, y luego haz clic 5 veces en el ícono de la app. Debería
aparecer una sección de depuración en la barra lateral.

---


## Compilar desde el código fuente

### Requisitos previos

- macOS 15 o posterior
- Xcode 26 o posterior



### Instalación

1. Clona el repositorio:
  ```bash
   git clone https://github.com/fparrav/facekey.git
   cd facekey
  ```
2. Ábrelo en Xcode:
  ```bash
   open facekey.xcodeproj
  ```
3. Configura tu equipo de firma (opcional, solo para firmar con tu propio Apple ID): crea
  `Local.xcconfig` junto a `Signing.xcconfig` con `DEVELOPMENT_TEAM = YOURTEAMID`. El archivo está
  en el gitignore, así que tu ID de equipo nunca llega a un commit.
4. Ejecuta el proyecto:
  - Haz clic en `run` o presiona `Cmd + R`.



## Contribuir

Por ahora no se aceptan PR. Este fork sigue mis propios planes, así que siéntete libre de hacer tu propio fork y llevarlo por tu camino. Si quieres lo que ofrece el original, o quieres contribuir a la app de la que todo esto creció, ve a [jonnyoo/glance](https://github.com/jonnyoo/glance).

Los comentarios sobre la app van a los [issues de GitHub](https://github.com/fparrav/facekey/issues).

El README existe en inglés y en español: un cambio en uno debe reflejarse en el otro (`README.md` y `README.es.md`).

## Agradecimientos

- **[glance](https://github.com/jonnyoo/glance)** de [Jonathan Zhou](https://github.com/jonnyoo): Facekey es un
fork de este proyecto. La idea original, la arquitectura y la mayor parte del código son obra suya.
- **[The Boring Notch](https://github.com/TheBoredTeam/boring.notch)**: por la física de la ventana del notch.
- **[InsightFace](https://github.com/deepinsight/insightface)**: el modelo ArcFace que hace el
reconocimiento.
- **[Alcove](https://tryalcove.com)**: gran inspiración de diseño.


## Licencia

[MIT](LICENSE) © Jonathan Zhou. Facekey es un fork de [glance](https://github.com/jonnyoo/glance); el
aviso de copyright original se conserva en `LICENSE`.
