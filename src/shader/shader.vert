#version 450

void main() {
	gl_Position = vec4(
		int(gl_VertexIndex) - 1,
		2 * int(gl_VertexIndex & 1) - 1,
		0, 1
	);
}
