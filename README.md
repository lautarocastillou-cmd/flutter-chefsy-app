# 🛵 Chefsy Cadete App (Flutter Native)

Esta aplicación nativa en **Flutter** reemplaza al portal web `chefsy.xyz/cadeteria` para eliminar por completo los crashes de Expo y evitar que el sistema operativo apague el rastreo GPS cuando el teléfono se guarda en el bolsillo.

---

## 🌟 Características Clave
1. **Rastreo en Bolsillo (Pantalla Apagada):** Utiliza un *Foreground Service* nativo en Android con notificación persistente para anular las restricciones de batería (*Doze Mode*).
2. **Conexión Directa a Chefsy:** Envía coordenadas filtradas (alta precisión) al endpoint `https://chefsy.xyz/api/public/ubicacion` cada 6 segundos.
3. **Portal Móvil Rápido:** Permite al cadete seleccionar su sesión, iniciar su turno con un botón gigante y avisar a sus clientes por WhatsApp con un solo toque.

---

## 🛠️ Cómo Compilar y Generar el APK

### Opción A: Compilar en tu PC (Si instalas Flutter)
1. Instala el SDK de Flutter desde [flutter.dev](https://docs.flutter.dev/get-started/install/windows).
2. Abre la terminal en esta carpeta (`app_cadete_flutter`) y ejecuta:
   ```bash
   flutter pub get
   flutter build apk --release
   ```
3. El archivo `.apk` listo para instalar en el celular del cadete se creará en:
   `build/app/outputs/flutter-apk/app-release.apk`

---

### Opción B: Compilar en la Nube GRATIS (Sin instalar Flutter en tu PC)
Si no quieres descargar los 2 GB de Flutter en tu computadora, puedes generar el APK desde la nube en 3 minutos:
1. Sube esta carpeta (`app_cadete_flutter`) a un repositorio en **GitHub**.
2. Conecta el repositorio a [Codemagic.io](https://codemagic.io) (gratis para proyectos Flutter).
3. Selecciona **Build Android APK**.
4. ¡Codemagic te enviará un link por correo para descargar el `.apk` directo al celular del cadete!

---

## 🔒 Permisos Nativos Configurados
El archivo `AndroidManifest.xml` ya incluye los permisos críticos:
- `FOREGROUND_SERVICE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `WAKE_LOCK` y `POST_NOTIFICATIONS`
