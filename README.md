# 🔄 rsync4me

> **Sincronizador interactivo de carpetas por SSH.**
> *Fusiona tus carpetas entre dos máquinas con un menú de terminal, sin borrar nada.*

---

[![Shell Script](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Linux-Arch%20%7C%20Debian%20%7C%20Fedora-blue?style=for-the-badge&logo=linux&logoColor=white)](https://www.kernel.org/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)

---

## ✨ Características

- 🎛️ **Panel interactivo con `fzf`:** menú visual en la terminal con vista previa de cada opción.
- 📂 **Selección de carpeta:** eliges el origen desde tus favoritas o explorando el disco, y el destino remoto navegando el servidor por SSH.
- 🔁 **Sincronización en ambos sentidos:** fusión bidireccional en una sola pasada de dos veces rsync.
- 🧪 **Simulación previa (dry-run):** ves exactamente qué se copiaría antes de tocar nada.
- ➕ **Solo añade:** usa `--ignore-existing` y **nunca** `--delete`. Nada se borra ni se sobrescribe en origen ni destino.
- ⚙️ **Configuración portable:** asistente de primera ejecución; nada está escrito en el código, funciona en cualquier equipo.
- 📦 **Exclusiones editables:** patrones `--exclude-from` en un archivo de texto.
- 🧾 **Registro:** historial de sincronizaciones en un log.
- 🖥️ **Línea de comandos:** opciones para automatizar sin abrir el menú.
- 🛠️ **Autoinstalación de dependencias:** detecta tu distro (`pacman`, `apt`, `dnf`) e instala lo que falte con confirmación.

---

## 🛠️ Requisitos

**Obligatorios** (sin ellos no funciona):

| Herramienta | Para qué |
|---|---|
| `bash` | Ejecutar el script |
| `rsync` | Motor de sincronización |
| `ssh` | Conexión con el servidor (`openssh`) |
| `fzf` | Menús interactivos |

**Recomendados** (opcionales, mejoran la experiencia):

| Herramienta | Para qué | Alternativa si falta |
|---|---|---|
| `less` | Leer el registro | `more` / `bat` / `cat` |
| `micro` | Editar exclusiones | `$EDITOR` / `nano` / `vi` |

El script detecta lo que falta y te propone instalarlo (`pacman`, `apt` o `dnf`). Si rechazas
las herramientas recomendadas, sigue funcionando con las alternativas.

---

## 🚀 Instalación

```bash
git clone https://github.com/DanSanMar/rsync4me.git ~/Proyectos/rsync4me
chmod +x ~/Proyectos/rsync4me/rsync4me.sh
```

Para invocarlo por su nombre desde cualquier carpeta:

```bash
ln -sf ~/Proyectos/rsync4me/rsync4me.sh ~/bin/rsync4me
```

> Asegúrate de que `~/bin` está en tu `PATH`.

En la **primera ejecución** se abre un asistente que pide:
servidor (host o IP), puerto SSH, usuario remoto y carpeta base remota.
Se guarda en `~/.config/rsync4me/config`.

---

## 🎮 Uso

```bash
rsync4me
```

Menú principal:

| Opción | Qué hace |
|---|---|
| 📂 SINCRONIZAR | Elige carpeta local, dirección y destino remoto, simula y ejecuta |
| 📋 MIS CARPETAS | Gestiona tus carpetas favoritas |
| ⚙️ SERVIDOR | Ajusta usuario, host, puerto y base remota |
| 📦 EXCLUSIONES | Edita los patrones `--exclude` |
| 🧾 REGISTRO | Consulta el historial |
| 💡 AYUDA | Atajos y comandos |
| ❌ SALIR | Cierra el panel |

### Navegación del panel

| Tecla | Acción |
|---|---|
| Escribir o flechas | Filtrar y moverse por la lista |
| Enter | Seleccionar la opción resaltada |
| Ctrl+/ | Mostrar u ocultar la vista previa |
| Esc / Ctrl+C | **En el menú principal:** abre el diálogo de salida. **En submenús o durante una sincronización:** cancela y vuelve al menú |
| Esc / Ctrl+C (2.ª vez, en <3 s) | Abre el diálogo de salida desde un submenú o una operación en curso |

Al abrirse el diálogo de salida, la primera opción es **SALIR**, así que basta con pulsar
**Enter** para cerrar el panel; **Esc** o elegir **SEGUIR** vuelve al menú.

### Sin menú (automatizable)

```bash
rsync4me --setup                    # Forzar el asistente de configuración
rsync4me --config /ruta/otro.conf   # Usar otra configuración
rsync4me -d ~/note4me               # Sincronizar (destino calculado solo)
rsync4me -d ~/note4me /backup/notes # Destino remoto explícito
rsync4me -d ~/note4me --push        # Solo esta máquina -> servidor
rsync4me -d ~/note4me --pull        # Solo servidor -> esta máquina
rsync4me -d ~/note4me --dry-run     # Simular sin copiar
```

---

## 📁 Configuración

Todo se guarda en `~/.config/rsync4me/`:

| Archivo | Contenido |
|---|---|
| `config` | Host, puerto, usuario y carpeta base remota |
| `carpetas.txt` | Carpetas favoritas (una por línea) |
| `exclude.txt` | Patrones que rsync ignorará |
| `rsync4me.log` | Registro de sincronizaciones |

Puedes cambiar el directorio con la variable `RSYNC4ME_CONFIG_DIR`, o el archivo con `--config`.

---

## 🔒 Cómo garantiza que no borra nada

- `--ignore-existing`: si un archivo ya existe en el destino, se omite (no se sobrescribe).
- **Nunca** se usa `--delete`, así que lo que esté en el destino y no en el origen permanece.
- El origen jamás se modifica salvo que tú ejecutes la dirección contraria.

> ⚠️ Si un archivo existe en **ambos** lados con el mismo nombre y distinto contenido, la fusión no lo reconcilia: cada lado conserva el suyo.

---

## 📝 Licencia

GPLv3. Consulta el archivo [LICENSE](LICENSE).
