shader_type spatial;
// 먼 산과 하늘 그림. 빛과 안개를 받지 않고, 아래쪽을 안개 색으로 흐려 지평선과 이어 붙인다.
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;

uniform sampler2D image : source_color, filter_linear, repeat_disable;
uniform vec3 fade_color : source_color = vec3(0.84, 0.9, 0.94);
// 그림 위에서부터 잰 세로 위치(0~1). fade_start부터 흐려지기 시작해 fade_end에서 완전히 안개 색이 된다
uniform float fade_start = 0.5;
uniform float fade_end = 0.8;

void fragment() {
	vec3 color = texture(image, UV).rgb;
	ALBEDO = mix(color, fade_color, smoothstep(fade_start, fade_end, UV.y));
}
