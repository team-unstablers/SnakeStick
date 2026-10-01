<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="Icono de la app SnakeStick: una mujer serpiente que ofrece una manzana roja">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Crea un instalador USB de arranque de Windows 10 / 11 en tu Mac.</b><br>
  Elige una ISO, elige una memoria USB y empieza. Sin Terminal, sin Boot Camp y sin dividir <code>install.wim</code>.
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="Descargar la última versión" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 26.6 o posterior" src="https://img.shields.io/badge/macOS-26.6%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 y 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="Licencia: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <b>Español</b> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick copiando una ISO de Windows 11 en una memoria USB, paso 6 de 8">
</p>

---

## ✨ ¿Por qué SnakeStick?

- 🪟 **Solo necesitas la app.** Elige una ISO de Windows 10 u 11 (o suéltala en la ventana), elige una memoria USB y haz clic en **Empezar a escribir**.
- 📦 **Los archivos de instalación grandes no son un problema.** Las ISO recientes de Windows traen un `install.wim` de más de
  4 GB, que no cabe en una memoria FAT32. SnakeStick pone Windows en una partición NTFS y añade una pequeña partición de
  arranque con el cargador [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs), la misma estructura que usa [Rufus](https://rufus.ie). No se divide nada.
- 🔐 **Funciona con Secure Boot.** El cargador de arranque incluido está firmado por Microsoft. Para los PC que han revocado el
  certificado de 2011 de Microsoft, SnakeStick puede usar los cargadores de arranque firmados con Windows UEFI CA 2023 de las ISO de Windows 11 25H2 o posterior.
- ✅ **Comprueba su propio trabajo.** Tras la escritura, vuelve a leer toda la memoria y la compara con la ISO, archivo por archivo.
- 🛡️ **No se acerca a los discos de tu Mac.** Solo aparecen los discos externos y extraíbles. Los discos internos y el disco de
  arranque nunca se muestran, el destino se vuelve a comprobar justo antes de escribir y no se borra nada hasta que lo confirmas.
- 🧹 **Sin restos del Mac.** La partición de Windows se escribe sin montarla nunca, así que en la memoria no acaban archivos
  `.DS_Store`, `._` ni `.fseventsd`.
- 🍎 **Una app nativa para Mac.** Escrita en Swift y SwiftUI, disponible en inglés, coreano, japonés, chino (simplificado y
  tradicional), alemán, francés, español, portugués (Brasil) y ruso. Libre y de código abierto bajo la GPLv3.

## 📥 Descarga

Descarga la última versión desde la pestaña **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)**
y mueve **SnakeStick** a tu carpeta **Aplicaciones**. La app está firmada y notarizada por Apple.

## 🧰 Qué necesitas

| | |
|---|---|
| **Mac** | macOS Tahoe 26.6 o posterior, y la contraseña de un administrador |
| **ISO de Windows** | Una ISO de instalación de Windows 10 u 11, por ejemplo de la página de descarga de [Windows 11](https://www.microsoft.com/es-es/software-download/windows11) o de [Windows 10](https://www.microsoft.com/es-es/software-download/windows10) de Microsoft |
| **Memoria USB** | Con capacidad suficiente para la ISO; las memorias demasiado pequeñas aparecen atenuadas. 16 GB es un tamaño seguro para las ISO actuales de Windows 11. |
| **PC de destino** | Un PC que arranque en modo UEFI. No se admite el arranque con BIOS heredada (CSM). |

> [!CAUTION]
> La escritura **borra todo** el contenido de la memoria USB seleccionada. Copia antes lo que quieras conservar.

## 🔑 Primer inicio: dos permisos que se conceden una sola vez

SnakeStick escribe en la memoria a través de una pequeña herramienta auxiliar que se ejecuta en segundo plano con privilegios
de administrador, así que la propia app nunca tiene que ejecutarse como root. macOS te pide que apruebes esa herramienta una vez:

1. **Permite la herramienta auxiliar.** La primera vez que hagas clic en **Empezar a escribir**, macOS te pedirá que permitas la
   herramienta auxiliar de SnakeStick. Activa **SnakeStick** en **Ajustes del Sistema › General › Ítems de inicio y extensiones** y vuelve a intentarlo.
2. **Concede el acceso total al disco.** macOS impide que las herramientas en segundo plano accedan a los discos extraíbles y a
   carpetas como **Descargas** a menos que la app tenga acceso total al disco. Añade **SnakeStick** en **Ajustes del Sistema ›
   Privacidad y seguridad › Acceso total al disco**. SnakeStick te avisa si falta este permiso y tiene un botón que abre la página correcta.

A partir de entonces, SnakeStick te pide la contraseña de administrador una vez cada vez que escribes una memoria.

## 🚀 Crear una memoria

1. **Elige la ISO.** Haz clic en **Elegir…** en **ISO de origen**, o suelta la ISO en la ventana. SnakeStick muestra la
   versión de Windows, la arquitectura y el tamaño.
2. **Elige la memoria.** Conéctala y selecciónala en **Disco de destino**.
3. **Revisa las opciones.**
   - **Nombre del volumen**: el nombre de la memoria. Por omisión es el nombre de la propia ISO.
   - **Verificar tras escribir**: activado por omisión. Añade unos minutos, y merece la pena.
   - **Usar cargadores de arranque firmados con Windows UEFI CA 2023**: solo es necesario en los PC que han revocado el
     certificado de Secure Boot de 2011 de Microsoft, y solo está disponible con ISO de Windows 11 25H2 o posterior. Si no estás seguro, déjalo desactivado.
4. **Haz clic en Empezar a escribir**, confirma con **Borrar y escribir** e introduce tu contraseña de administrador.
5. **Espera.** La barra de progreso muestra el paso actual (8 en total) y el tiempo restante. En la memoria USB 3 que
   probamos, una ISO de Windows 11 de 8,7 GB tardó unos 16 minutos, verificación incluida.
6. Cuando SnakeStick indique que ha terminado, haz clic en **Expulsar** para retirar la memoria.

Puedes hacer clic en **Detener** en cualquier momento. La memoria quedará sin poder arrancar, y si la vuelves a escribir, se empieza desde el principio.

## 💻 Arrancar el PC desde la memoria

1. Conecta la memoria al PC y enciéndelo mientras presionas la tecla del menú de arranque. Suele ser **F12**, **F11**, **F8**
   o **Esc**; consulta el manual de tu PC.
2. Elige la entrada **UEFI** de la memoria USB.
3. Se inicia el programa de instalación de Windows.

Si el PC no arranca desde la memoria con Secure Boot activado, busca en los ajustes del firmware una opción como
**"Allow Microsoft 3rd Party UEFI CA"** y actívala. Algunos PC, en especial los Secured-core PC, vienen con ella desactivada,
y el cargador de arranque UEFI:NTFS la necesita. También puedes desactivar Secure Boot durante la instalación; vuelve a
activarlo después.

## ❓ Preguntas frecuentes

<details>
<summary><b>¿Por qué necesita acceso total al disco?</b></summary>
<br>

La parte de SnakeStick que escribe en la memoria es una herramienta auxiliar en segundo plano (un daemon de launchd). macOS no
permite que estas herramientas abran discos extraíbles ni lean una ISO en carpetas como Descargas a menos que la app a la que
pertenecen tenga acceso total al disco, y no hay ningún permiso más limitado que una herramienta auxiliar pueda pedir. Se lo
concedes a la app SnakeStick, y llega a la herramienta auxiliar que hay dentro de la app.

</details>

<details>
<summary><b>¿Por qué no formatear la memoria en FAT32, como hacía el Asistente Boot Camp?</b></summary>
<br>

FAT32 no admite archivos de 4 GB o más, y `sources/install.wim` en las ISO actuales de Windows suele superar ese tamaño. La
solución habitual es dividir el archivo. SnakeStick, en cambio, lo mantiene entero en una partición NTFS, y una diminuta
partición FAT a su lado contiene el cargador UEFI:NTFS, que enseña al firmware del PC a leer NTFS.

</details>

<details>
<summary><b>¿Puede saltarse los requisitos de TPM o Secure Boot de Windows 11?</b></summary>
<br>

No. SnakeStick copia la ISO tal cual. No elude los requisitos de hardware, no añade archivos de respuesta para instalaciones
desatendidas ni inyecta controladores.

</details>

<details>
<summary><b>¿Qué pasa si saco la memoria o detengo el proceso a medias?</b></summary>
<br>

SnakeStick limpia lo que ha dejado a medias, y la memoria queda sin poder arrancar. Vuelve a escribirla y quedará bien. Los
discos de tu Mac nunca se tocan.

</details>

<details>
<summary><b>¿Puedo crear una imagen de disco en lugar de escribir en una memoria?</b></summary>
<br>

Desde la app, no. SnakeStick solo escribe en memorias USB.

</details>

> [!NOTE]
> SnakeStick es joven. Las memorias creadas con él han arrancado hasta el programa de instalación de Windows en un PC x64 con
> Secure Boot activado, pero todavía no se ha probado una instalación completa de Windows desde una de ellas. Si algo falla,
> [abre una incidencia](https://github.com/team-unstablers/SnakeStick/issues) y adjunta el registro (**Mostrar registro…** en la app).

## 🙏 Construido sobre

SnakeStick no existiría sin este software libre. ¡Gracias!

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): crea y escribe la partición NTFS
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): el cargador de arranque que permite al firmware UEFI iniciar Windows desde NTFS
- [wimlib](https://github.com/ebiggers/wimlib): lee la imagen de arranque de Windows
- [Rufus](https://github.com/pbatard/rufus): su código fuente se usó como referencia

SnakeStick lo ha escrito un agente de programación basado en un LLM bajo supervisión humana.

## 🐍 Sobre el icono

La serpiente del Edén, ofreciendo una manzana a tu Mac. La manzana está entera: nadie le ha dado un mordisco todavía.

## 🛠️ Para desarrolladores

Cómo funciona SnakeStick, cómo compilarlo desde el código fuente y cómo ejecutar las pruebas: consulta [docs/DESIGN.md](docs/DESIGN.md) (en inglés).

## 📄 Licencia

SnakeStick es software libre bajo la [GNU General Public License v3.0 o posterior](COPYING). Se ofrece sin ninguna garantía.
Los componentes incluidos conservan sus propias licencias; consulta [docs/DESIGN.md](docs/DESIGN.md#license).
