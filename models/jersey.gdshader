shader_type spatial;
// Maglia nel colore della squadra + pedalata simulata spostando i punti delle gambe.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear_mipmap;
uniform vec4 team_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

uniform float pedal_on = 0.0;      // 1 sul corpo, 0 sulle ruote
uniform vec3 fwd_axis = vec3(1.0, 0.0, 0.0);   // direzione di marcia nel modello
uniform vec3 lat_axis = vec3(0.0, 0.0, 1.0);
uniform float lat0 = 0.0;          // piano della bici
uniform float crank_fwd = 0.0;     // movimento centrale
uniform float crank_y = 0.01;
uniform float crank_len = 0.005;   // raggio del cerchio dei piedi
uniform float hip_y = 0.028;       // sopra l'anca non si muove nulla
uniform float reach = 0.013;       // estensione delle gambe avanti e indietro
uniform float phase = 0.0;         // angolo della pedivella
uniform float wheel_on = 0.0;      // 1 sulle ruote: normali laterali, illuminazione stabile mentre girano

void vertex() {
	if (wheel_on > 0.5) {
		NORMAL = lat_axis * (dot(VERTEX, lat_axis) >= 0.0 ? 1.0 : -1.0);
	}
	if (pedal_on > 0.5) {
		float lat = dot(VERTEX, lat_axis) - lat0;
		float w_lat = smoothstep(0.0016, 0.003, abs(lat));          // fuori dal telaio
		float fw = dot(VERTEX, fwd_axis) - crank_fwd;
		float w_fwd = 1.0 - smoothstep(reach * 0.75, reach, abs(fw)); // vicino ai pedali
		float w_y = clamp((hip_y - VERTEX.y) / max(0.0001, hip_y - crank_y), 0.0, 1.0);
		float w = w_lat * w_fwd * w_y;
		float ph = phase + (lat > 0.0 ? 0.0 : 3.14159265);           // gambe in opposizione
		// giro della pedivella nel verso di marcia: davanti -> giù -> dietro -> su
		VERTEX += (fwd_axis * cos(ph) - vec3(0.0, 1.0, 0.0) * sin(ph)) * crank_len * w;
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float m = texture(mask_tex, UV).r;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 tinted = team_color.rgb * (0.35 + 1.3 * l);
	ALBEDO = mix(c, tinted, m);
	ROUGHNESS = 0.85;
}
