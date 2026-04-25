# Guía de Configuración - Juego 3D Godot

## 📋 Pasos pendientes

### Paso 1: Exportar modelo de Blender ✅ (Necesario)
1. Abre el archivo `marco.blend` en Blender
2. Ve a **File → Export → glTF 2.0 (.glb/.gltf)**
3. Marca estas opciones:
   - ✅ Apply Modifiers
   - ✅ Include All Bone Influences
   - ✅ Include Animations (si tiene)
   - ✅ Include Custom Properties
4. Guarda como **marco.gltf** en la carpeta `/models/`

### Paso 2: Crear las escenas en Godot

#### 2a. Escena Level.tscn
1. Crea nueva escena 3D (Node3D como raíz)
2. Añade:
   - CSGBox3D para el suelo (escala: 20x1x20)
   - Algunos obstáculos decorativos (CSGBox3D más pequeños)
   - Asigna el script `scripts/level.gd`
   - Añade CanvasLayer con Label para UI

#### 2b. Escena Player.tscn
1. Crea nueva escena con CharacterBody3D como raíz
2. Añade como hijo:
   - El modelo importado (marco.gltf)
   - CollisionShape3D (capsule que ajuste al personaje)
   - Camera3D (en tercera persona, posición: Y=2, Z=3)
3. Asigna el script `scripts/player.gd`
4. Añade al grupo "player"

#### 2c. Escena NPC.tscn
1. Crea nueva escena con CharacterBody3D como raíz
2. Añade como hijo:
   - Modelo visual simple (o copia del marco con diferente color)
   - CollisionShape3D
3. Asigna el script `scripts/npc.gd`
4. Añade al grupo "npc"

### Paso 3: Configurar Input Map
En **Project → Project Settings → Input Map**, añade:
- `move_forward` → W (o Flecha Arriba)
- `move_back` → S (o Flecha Abajo)
- `move_left` → A (o Flecha Izquierda)
- `move_right` → D (o Flecha Derecha)

### Paso 4: Instancia NPCs en el nivel
En Level.tscn, arrastra varias copias de NPC.tscn en diferentes posiciones

## 📁 Estructura actual
```
juego-3d/
├── scenes/          (aquí irán las .tscn)
├── scripts/         (scripts GDScript listos)
├── models/          (aquí va marco.gltf después de exportar)
├── assets/          (texturas, materiales, etc.)
├── marco.blend      (exportar desde aquí)
└── project.godot
```

## ⚙️ Configuración de NPCs en el inspector
Para NPCs con movimiento lineal:
- movement_type = "linear"
- point_a = posición inicial
- point_b = posición final
- speed = 3.0

Para NPCs con movimiento aleatorio:
- movement_type = "random"
- random_area = 5.0
- change_direction_interval = 2.0

## 🎮 Controles del juego
- WASD o Flechas: Mover personaje
- Si chocas con un NPC: vuelves al punto de inicio
