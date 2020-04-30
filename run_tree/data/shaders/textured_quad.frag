#version 330 core

out vec4 out_frag_color;
in vec2 texture_coords;
in vec4 vertex_color;
in vec3 vertex_normal;
in vec3 ws_frag_position;

// uniform mat4 view;

struct Material {
    vec4 BaseColor;
    float Roughness;
    float Metallic;

    bool enable_diffuse_texture;
    sampler2D diffuse_texture;
};

struct Light {
    vec3 direction;
    vec3 radiance;

    sampler2D shadow_map;
    int use_shadow_map;
    mat4 projection_view_matrix;
    float shadow_map_size;
};

struct Camera {
    vec3 position;
};

uniform Camera camera;

const int MAX_LIGHTS = 8;

uniform int   num_lights;
uniform Light lights[MAX_LIGHTS];

uniform Material the_material;

const float PI = 3.14159265359;

float ggx_ndf(float a, float n_dot_h) {
    float a2 = a*a;
    float factor = ((n_dot_h*n_dot_h) * (a2 - 1) + 1);
    float denom = PI * factor*factor;

    return a2 / denom;
}

float schlick_ggx_sub(float n_dot_v, float k) {
    return n_dot_v / (n_dot_v*(1 - k) + k);
}

float schlick_ggx(float n_dot_l, float n_dot_v, float Roughness) {
    float r1 = Roughness + 1;
    float k = (r1*r1) / 8;

    return schlick_ggx_sub(n_dot_l, k) * schlick_ggx_sub(n_dot_v, k);
}

vec3 schlick_fresnel(float v_dot_h, vec3 F0) {
    return F0 + (1 - F0)*pow(2, (-5.55473*v_dot_h - 6.98316) * v_dot_h);
}

vec3 microfacet_specular_brdf(vec3 V, vec3 N, vec3 H, vec3 L, float Roughness, vec3 F0) {
    float n_dot_h = max(0.0, dot(N, H));
    float v_dot_h = max(0.0, dot(V, H));
    float n_dot_l = max(0.0, dot(N, L));
    float n_dot_v = max(0.0, dot(N, V));
    vec3 numer = ggx_ndf(Roughness*Roughness, n_dot_h) * schlick_fresnel(v_dot_h, F0) * schlick_ggx(n_dot_l, n_dot_v, Roughness);
    float denom = max(4*n_dot_l*n_dot_v, 0.0001);
    return numer / denom;
}

vec4 gamma_correct(vec4 color) {
    vec4 new_color = color;
    // @Temporary we probably want to accept the gamma value from the user.
    new_color.xyz = pow(color.xyz, vec3(1/2.2));
    return new_color;
}

float get_shadow_factor(Light light, vec2 texcoord_offset) {
    if (light.use_shadow_map != 0) {
        vec4 LS_frag_pos = light.projection_view_matrix * vec4(ws_frag_position, 1);
        LS_frag_pos.xyz /= LS_frag_pos.w;

        LS_frag_pos.xyz = LS_frag_pos.xyz * 0.5 + 0.5;

        LS_frag_pos.xy += texcoord_offset;

        if (LS_frag_pos.x < 0 || LS_frag_pos.x > 1.0) return 0.0;
        if (LS_frag_pos.y < 0 || LS_frag_pos.y > 1.0) return 0.0;

        float closet_distance_to_list = texture(light.shadow_map, LS_frag_pos.xy).r;
        const float BIAS = 0.001;

        if (closet_distance_to_list + BIAS < LS_frag_pos.z) return 1.0;
        else return 0.0;
    } else {
        return 0.0;
    }
}

float get_shadow_factor_pcf(Light light) {
    float TEXEL_SIZE = 1.0/(light.shadow_map_size * 2); // @Temporary

    float total = 0;
    const int SIZE = 3;
    for (int x = -SIZE; x <= SIZE; ++x) {
        for (int y = -SIZE; y <= SIZE; ++y) {
            vec2 offset = vec2(TEXEL_SIZE * x, TEXEL_SIZE * y);
            float dist = get_shadow_factor(light, offset);
            float wx = 1.0 - (x / (SIZE*2+1));
            float wy = 1.0 - (y / (SIZE*2+1));
            float weight = (wx + wy) / 2.0;

            total += dist * weight;
        }
    }

    return total / ((SIZE*2.0+1.0) * (SIZE*2.0+1.0));
}

void main() {
    vec4 diffuse_texture_color = vec4(1, 1, 1, 1);
    if (the_material.enable_diffuse_texture) {
        diffuse_texture_color = texture(the_material.diffuse_texture, texture_coords);
    }

    vec4 base_color = vertex_color * the_material.BaseColor * diffuse_texture_color;
    vec4 ambient = base_color * vec4(0.09);

    vec3 F0 = vec3(0.04);
    float Roughness = the_material.Roughness;

    if (length(vertex_normal) > 0.25) {
        vec4 color = vec4(0, 0, 0, 1);

        vec3 N = normalize(vertex_normal);
        vec3 V = normalize(camera.position - ws_frag_position);
        for (int i = 0; i < num_lights; ++i) {
            vec3 L = normalize(-lights[i].direction);
            vec3 H = normalize(V + L);

            float n_dot_l = max(dot(N, L), 0);

            if (n_dot_l > 0) {
                vec3 ks = microfacet_specular_brdf(V, N, H, L, Roughness, F0);
                vec3 kd = 1 - ks;

                float shadow_factor = get_shadow_factor_pcf(lights[i]);
                color.xyz += (ks*lights[i].radiance + kd*(base_color.xyz / PI)) * n_dot_l * (1.0 - shadow_factor);
            }
        }

        out_frag_color = gamma_correct(ambient + color);
        return;
    }
    
    out_frag_color = base_color;
}
