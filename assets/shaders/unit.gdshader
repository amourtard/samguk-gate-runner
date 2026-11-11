shader_type spatial;
// 병사, 장수, 길가 소품 공용 재질.
// 꼭짓점 색의 알파가 1이면 팀 색(아군 파랑, 적 빨강, 계열 색)에 꼭짓점 색을 곱한 명암을 쓰고,
// 0이면 꼭짓점 색을 그대로 쓴다(피부, 나무, 쇠 같은 고정 색).
// 달리기 흔들림은 인스턴스 사용자 데이터의 r 값을 박자 어긋남으로 쓴다.

uniform vec4 team_color : source_color = vec4(1.0);
uniform float bob_height = 0.0;
uniform float bob_speed = 12.0;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	VERTEX.y += bob_height * abs(sin(TIME * bob_speed + phase));
}

void fragment() {
	vec3 team = team_color.rgb * COLOR.rgb;
	ALBEDO = mix(COLOR.rgb, team, COLOR.a);
	ROUGHNESS = 0.85;
}
