extends Node2D

# Diccionario de velocidades (SOLO para los planetas normales)
# Ajusta los números si quieres que giren más rápido o lento.
var velocidades = {
	"Mercurio": 0.1,
	"Venus": -0.05,
	"Tierra": 1.0,
	"Marte": 0.9,
	"Jupiter": 2.5,
	"Saturno": 2.3,
	"Urano": -1.5,
	"Neptuno": 1.6
}

func _process(delta):
	# --- 1. ROTACIÓN DEL SOL ---
	# El "if" verifica si existe el nodo "Sol" antes de intentar rotarlo.
	# Esto evita el error "null instance" si te olvidaste de moverlo.
	if has_node("Sol"):
		$Sol.rotation += 0.05 * delta
	
	# --- 2. ROTACIÓN DE LOS PLANETAS ---
	# Recorremos solo los nodos que están DENTRO de la carpeta "Planetas"
	for planeta in $Planetas.get_children():
		
		# (Opcional) Si por error dejaste el Sol dentro de la carpeta Planetas,
		# esta línea evita que gire rápido como los demás.
		if planeta.name == "Sol":
			continue 
			
		# Buscamos la velocidad en el diccionario. 
		# Si el planeta no está en la lista, usa 0.5 por defecto.
		var velocidad_base = velocidades.get(planeta.name, 0.5)
		
		# Aplicamos la rotación
		planeta.rotation += velocidad_base * delta
