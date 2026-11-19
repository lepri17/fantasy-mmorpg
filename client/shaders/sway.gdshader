// Trees sway in the wind: the top of the picture moves side to side, the
// foot stays put. Each tree sways in its own time (from where it stands), so
// a forest does not move in step. game_map.gd gives every tree this material.
shader_type canvas_item;

uniform float strength = 7.0; // how far the top moves, in the picture's pixels
uniform float speed = 1.1;

void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.013 + MODEL_MATRIX[3].y * 0.009;
	float top = 1.0 - UV.y;
	float wind = sin(TIME * speed + phase) + 0.35 * sin(TIME * speed * 2.3 + phase * 1.7);
	VERTEX.x += wind * strength * top;
}
