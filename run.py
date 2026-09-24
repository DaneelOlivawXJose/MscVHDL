import os
from pathlib import Path
from vunit import VUnit

# 1. Inicializar VUnit
ui = VUnit.from_argv(compile_builtins=False)
ui.add_vhdl_builtins()

# 2. Definir ruta base
ROOT = Path(__file__).resolve().parent

# 3. Crear la librería
lib = ui.add_library("msc_lib")

# 4. Añadir TODOS los archivos VHDL usando búsqueda recursiva
# Esto busca lib_config.vhd si está suelto en la raíz
# 4. Añadir TODOS los archivos VHDL usando búsqueda recursiva
# El parámetro allow_empty=True evita que el script explote si una ruta está vacía.

# 4. Añadir archivos fuente y testbenches
lib.add_source_files(ROOT / "hdl" / "**" / "*.vhd")
lib.add_source_files(ROOT / "tb" / "**" / "*.vhd")

# 5. Configurar opciones de GHDL (Corregido el Warning de a_flags)
ui.set_sim_option("ghdl.sim_flags", ["--wave=waves.ghw"])
ui.set_compile_option("ghdl.a_flags", ["--std=08"])

# 6. Ejecutar
if __name__ == "__main__":
    ui.main()