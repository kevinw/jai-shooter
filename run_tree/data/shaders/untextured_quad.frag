#version 330 core

out vec4 out_frag_color;
in vec2 texture_coords;
in vec4 vertex_color;
in vec3 vertex_normal;
in vec3 ws_frag_position;

void main() {
    out_frag_color = vertex_color;
}
