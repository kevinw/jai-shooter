#version 330 core

layout (location = 0) in vec3 in_pos;
layout (location = 1) in vec2 in_texture_coords;
layout (location = 2) in vec4 in_vertex_color;
layout (location = 3) in vec3 in_normal;

out vec2 texture_coords;
out vec4 vertex_color;
out vec3 vertex_normal;
out vec3 ws_frag_position;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    vertex_color = in_vertex_color;
    texture_coords = in_texture_coords;
    mat4 modelview = view * model;
    vertex_normal = (transpose(inverse(model)) * vec4(in_normal, 0.0)).xyz;
    ws_frag_position = (model * vec4(in_pos, 1.0)).xyz;
    gl_Position = projection * modelview * vec4(in_pos, 1.0);
}
