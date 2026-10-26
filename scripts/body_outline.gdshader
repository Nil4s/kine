// the body's outline (main.gd BODY_OUTLINE_SHADER): back faces grown along the normal, unshaded, and pushed deeper in the depth buffer
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 colour : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float grow = 0.0045;
instance uniform float outline_on = 1.0;   // 0 on a part that wears a pick / hover tint: collapsed, nothing is drawn
uniform float push = 0.002;   // clip-space depth the hull sits behind the skin: a neighbour's hull never covers a part's own surface

void vertex() {
	if (outline_on < 0.5) {
		VERTEX = vec3(0.0);
	} else {
		vec4 p = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * grow, 1.0));
		p.z -= push * p.w;
		POSITION = p;
	}
}

void fragment() {
	ALBEDO = colour.rgb;
}
