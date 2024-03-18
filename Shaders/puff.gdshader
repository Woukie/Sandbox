shader_type spatial;
render_mode unshaded;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 2.0);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
