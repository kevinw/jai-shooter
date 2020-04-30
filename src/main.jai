#import "Basic";
#import "GL";
#import "Window_Creation";
#import "Input";
#import "Render";
Pool :: #import "Pool";
#import "File";
#import "Random";
#import "Sound_Player";
#import "String";
#import "Math";
#import "Gamepad";
#import "System";

#load "config.jai";
#load "render.jai";
#load "obj_loader.jai";
#load "util.jai";
#load "physics.jai";

#if OS_WINDOWS {
    // press ` (~) to show the imgui debug ui for editing settings live.
    DEBUG_UI :: true; 
} else {
    // TODO: implement some of the imgui input bits for non windows platforms
    // (Input module doesn't have mouse move events)
    DEBUG_UI :: false; 
}

#if DEBUG_UI {
    #load "imgui_inspector.jai";
}

#if OS_MACOSX {
    #load "macosx.jai"; // Cocoa app stuff/entry point
}

Direction :: enum { UP; DOWN; LEFT; RIGHT; }
direction_vectors: [4]Vector2;

Bullet :: struct {
    using aabb: AABB;
    vel: Vector2;
    life_timer: float = 4;
    friendly: bool = true; // fired by player
}

Actor :: struct {
    using aabb: AABB;

    look_direction: Vector2;
    hurt_cooldown: float;
}

Enemy_State :: enum {
    WAITING;
    CHASING_PLAYER;
    FIRING;
    SPAWNING;
}

Enemy :: struct {
    using actor: Actor;

    state: Enemy_State;
    timer: float;

    shoot_cooldown: float;
    shoot_angle: float;
}

STARTING_HEALTH :: 3;

Player :: struct {
    using actor: Actor;

    health := STARTING_HEALTH;

    walk_rotate: float;
    walk_dir: s8 = 1;
    time_since_last_fire: float;
}

Occupant :: enum {
    EMPTY :: 0;
    HEAD :: 1;
    BODY :: 2;
    APPLE_1 :: 3;
    APPLE_2 :: 4;
    APPLE_3 :: 5;
    ROCK :: 6;
}

Menu_Selection :: enum s8 {
    CONTINUE_GAME :: 0;
    RESET_GAME :: 1;
    QUIT :: 2;
};
Menu_Selection_MAX :: 2;

FONT_HEIGHT :: 28;

LOW_SHADOW_MAP_SIZE    :: 512;
MEDIUM_SHADOW_MAP_SIZE :: 1024;
HIGH_SHADOW_MAP_SIZE   :: 2048;

PLAY_AREA_SIZE :: 11;

game: struct {
    static: [..]AABB;

    settings: struct {
        mute_all_sounds: bool;
        enemy: struct {
            size := 0.45;
            fire_rate := 0.3;
            move_speed := 3.2;
            bullet_speed := 5.0;
            shoot_angle_speed := 1.05;
            spawn_delay_min := 0.6;
            spawn_delay_max := 2.3;
            max_count := 6;
            spawn_at_a_time := 2.0;
            initial_spawn_count := 0; // 5;
        };
        player: struct {
            size := 0.3;
            speed := 9.0;
            hurt_cooldown := 1.0;
            hurt_screenshake := 0.42;
            bullet_speed := 15.0;
            fire_rate := 0.15;
            move_speed_add_to_bullet := 3.0;
        };
        bullet_size := 0.05;
        visual_bullet_size := 0.5;
        camera: struct {
            pos: Vector3;
            pos.x = 0;
            pos.y = 6.74;
            pos.z = 1.75;
        };
        sun_light: struct {
            radiance: Vector3;
            radiance.x = 3.2;
            radiance.y = 2.0;
            radiance.z = 0.8;
            
            direction: Vector3;
            direction.x = -0.4;
            direction.y = -0.8;
            direction.z = -1;
        };
    };

    stats: struct {
        num_enemies_defeated: u32;
    };

    time_scale := 1.0;

    pool: Pool.Pool;
    FPS := 0;
    rendered_frame_count:s64 = 0;
    fps_time := 0.0;
    gamepad_time := 0.0;
    last_time: float64;
    elapsed_time: float64;
    fullscreen := false;
    saved_window_info: Saved_Window_Info;

    game_framebuffer: Framebuffer;
    textured_quad_shader: GLuint;
    untextured_quad_shader: GLuint;

    lights: [..] *Light;

    //camera_position: Vector3;

    font: *Dynamic_Font;
    sound_player: *Sound_Player;
    ambience: *Mixer_Sound_Data;
    eat_sound: *Mixer_Sound_Data;
    arrow_sound: *Mixer_Sound_Data;
    hit_wall_sound: *Mixer_Sound_Data;
    hurt_sound: *Mixer_Sound_Data;
    window_width: s32;
    window_height: s32;

    immediate_draw_buffer_id: u32;

    shadow_map_size: s32 = MEDIUM_SHADOW_MAP_SIZE;

    msaa := true;
    
    projection: Matrix4;
    view: Matrix4; // conceptually the transform of the camera from (0,0,0), the shader will invert this

    mode: enum {
        GAME;
        MENU;
    };

    menu_selection: Menu_Selection;
    quit := false;

    down_pressed := false;
    up_pressed := false;
    left_pressed := false;
    right_pressed := false;
    enter_pressed := false;

    // input states
    firing_in_direction: [4]bool;
    input_direction: [4]bool;
    fire_time_cooldown: float;

    player_has_crashed := false;
    
    snake_head: *Model;
    fruit: *Model;
    wall: *Model;
    tree: [] *Model;
    generic_floor_tile: *Model;

    grid_size: u32 = PLAY_AREA_SIZE; // width and height of the grid
    grid_offset_x: float;
    grid_offset_y: float;
    
    player: Player;
    bullets: [..]Bullet;
    enemies: [..]Enemy;
    enemy_spawn_cooldown: float;

    screen_shake_percent := 1.0;
    screen_shake_step := 2.1;
    shake_amount := 1.0;

    fps_string: string;
};

bake_and_concat_mesh :: (target: *Mesh, source: *Mesh) {
    for source.vertices {
        input_vertex := it;
        input_vertex.position = (source.model_matrix * make_vector4(input_vertex.position, 1)).xyz;
        array_add(*target.vertices, input_vertex);
    }
}

generate_floor_model_from_tile :: (tile: *Model, size: s32) -> *Model {
    model := New(Model);
    
    for tile.meshes {
        mesh := New(Mesh);
        mesh.material = it.material;
        array_add(*model.meshes, mesh);
    }

    for x: -size..size*2 {
        for y: -size..size*2 {
            model_matrix := make_translation_matrix4(make_vector3(game.grid_offset_x + x, 0, game.grid_offset_y + y));

            for tile.meshes {
                it.model_matrix = model_matrix;
                bake_and_concat_mesh(model.meshes[it_index], it);
            }
        }
    }

    return model;
}

generate_wall_model_from_tile :: (tile: *Model) -> *Model {
    result := New(Model);

    for tile.meshes {
        mesh := New(Mesh);
        mesh.material = it.material;
        array_add(*result.meshes, mesh);
    }

    make_wall_jitter_vector3 :: (x: float, y: float, z: float) -> Vector3 {
        C :: 0.15;
        return make_vector3(
            x + random_get_within_range(0, C),
            y + random_get_within_range(0, C),
            z + random_get_within_range(0, C),
        );
    }

    { // East wall
        model := tile;

        for y: 0..game.grid_size-1 {
            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x + game.grid_size + 1,  0, y + game.grid_offset_y));
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x + game.grid_size + 1,  0, y + game.grid_offset_y + 0.5));
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x + game.grid_size + 1,  0, game.grid_offset_y + game.grid_size));
            bake_and_concat_mesh(result.meshes[it_index], it);
        }
    }

    { // West wall
        model := tile;
        q: Quaternion;
        set_from_axis_and_angle(*q, 0.0, 1.0, 0.0, PI);
        rot := make_rotation_matrix4(q);

        for y: 0..game.grid_size-1 {
            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x-1,  0, y + game.grid_offset_y + 0.5)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x-1,  0, y + game.grid_offset_y + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x-1,  0, game.grid_offset_y)) * rot;
            bake_and_concat_mesh(result.meshes[it_index], it);
        }
    }

    { // North wall
        model := tile;
        q: Quaternion;
        set_from_axis_and_angle(*q, 0.0, 1.0, 0.0, PI/2);
        rot := make_rotation_matrix4(q);

        for x: 0..game.grid_size-1 {            

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(x + game.grid_offset_x + 0.5,  0, game.grid_offset_y-1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(x + game.grid_offset_x + 1,  0, game.grid_offset_y-1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x,  0, game.grid_offset_y-1)) * rot;
            bake_and_concat_mesh(result.meshes[it_index], it);
        }
    }

    { // South wall
        model := tile;
        q: Quaternion;
        set_from_axis_and_angle(*q, 0.0, 1.0, 0.0, -PI/2);
        rot := make_rotation_matrix4(q);

        for x: 0..game.grid_size-1 {

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(x + game.grid_offset_x,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(x + game.grid_offset_x + 0.5,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_wall_jitter_vector3(game.grid_offset_x + game.grid_size,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
            bake_and_concat_mesh(result.meshes[it_index], it);
        }
    }

    return result;
}

ease_out_elastic :: (n: float) -> float {
    p := 0.3;
    return pow(2, -10*n) * sin((n-p/4.0) * TAU/p) + 1;
}

render_game :: () {
    glClearColor(0.0, 0.6, 0.1, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    view := game.view;
    defer game.view = view;

    {
        max_offset := 1.0;
        max_roll := PI / 16;
        max_pitch := PI / 16;
        max_yaw := PI / 16;
        shake_z := (1.0 - game.screen_shake_percent) * random_get_within_range(-1, 1) * max_roll * game.shake_amount;
        shake_y := (1.0 - game.screen_shake_percent) * random_get_within_range(-1, 1) * max_yaw * game.shake_amount;
        shake_x := (1.0 - game.screen_shake_percent) * random_get_within_range(-1 , 1) * max_pitch * game.shake_amount;
        offset_z := (1.0 - game.screen_shake_percent) * random_get_within_range(-1, 1) * max_offset * game.shake_amount;
        offset_y := (1.0 - game.screen_shake_percent) * random_get_within_range(-1, 1) * max_offset * game.shake_amount;
        offset_x := (1.0 - game.screen_shake_percent) * random_get_within_range(-1 , 1) * max_offset * game.shake_amount;

        q: Quaternion;
        set_from_axis_and_angle(*q, 0.0, 0.0, 1.0, shake_z);
        rot := make_rotation_matrix4(q);
        set_from_axis_and_angle(*q, 0.0, 1.0, 0.0, shake_y);
        rot *= make_rotation_matrix4(q);
        set_from_axis_and_angle(*q, 1.0, 0.0, 0.0, shake_x);
        rot *= make_rotation_matrix4(q);
        game.view *= (make_translation_matrix4(make_vector3(offset_x, offset_y, offset_z)) * rot);
    }

    glEnable(GL_DEPTH_TEST);
    defer glDisable(GL_DEPTH_TEST);

    // draw floor

    // Hmm.. I'm not sure what an appropriate amount of floor tiles to render are without just going nuts
    // otherwise the camera may see empty space instead of floor!
    grid_size := cast(s32) game.grid_size;

    {
        model := game.generic_floor_tile;
        model.meshes[0].material.diffuse = make_vector3(0.3, 1.0, 0.4);
        model_matrix := matrix4_identity();

        for model.meshes {
            it.model_matrix = model_matrix;
            render_mesh(it);
        }
    }

    DRAW_GRID :: false;
    if DRAW_GRID {
        glDisable(GL_DEPTH_TEST);
        // draw grid
        color := make_vector4(1.0, 1.0, 1.0, 1.0);
        for x: 0..game.grid_size {
            draw_line(make_Quad(xx x + game.grid_offset_x, 0 + game.grid_offset_y, 0, cast(float) game.grid_size), color);
        }
        
        for y: 0..game.grid_size {
            draw_line(make_Quad(0 + game.grid_offset_x, xx y + game.grid_offset_y, cast(float) game.grid_size, 0), color);
        }
        glEnable(GL_DEPTH_TEST);
    }

    bias :: 0.5;

    {
        model := game.wall;
        model_matrix := make_translation_matrix4(make_vector3(game.grid_offset_x, 0, game.grid_offset_y));
        for model.meshes {
            it.material.diffuse = make_vector3(0.4, 0.2, 0.2);
            it.model_matrix = model_matrix;
            render_mesh(it);
        }
    }

    RENDER_TREES :: true;

    render_model :: inline (model: *Model) {
        for model.meshes
            render_mesh(it);
    }

    if RENDER_TREES {
    for x: -4..-1 {
        for y: -1..cast(s32) (game.grid_size/4 + 1) {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 2), 0, game.grid_offset_y + (y*4) - (x % 2)*2)); }
            for models render_model(it);
        }
    }

    for x: 1..4 {
        for y: -1..cast(s32) (game.grid_size/4 + 1) {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size + (x * 2), 0, game.grid_offset_y + (y*4) - (x % 2)*2)); }
            for models render_model(it);
        }
    }

    for x: 0..game.grid_size/4 {
        for y: -4..-1 {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 4) - (y % 2)*2, 0, game.grid_offset_y + (y*2))); }
            for models render_model(it);
        }
    }

    for x: 0..(game.grid_size/4)+1 {
        for y: 1..4 {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 4) - (y % 2)*2, 0, game.grid_offset_y + game.grid_size + (y*2))); }
            for models render_model(it);
        }
    }
    } // RENDER_TREES

    actor_model_matrix :: (using actor: *Actor, scale:float = 1, extra_rot:float = 0) -> Matrix4 {
        translation := make_translation_matrix4(make_vector3(pos.x + game.grid_offset_x + bias, bias, pos.y + game.grid_offset_y + bias));

        q: Quaternion;
        set_from_axis_and_angle(*q, 0, 1, 0, TAU * .25 + angle_radians_vec2(look_direction));
            
        scl: Matrix4 = matrix4_identity();
        if scale != 1 scl = make_scale_matrix(scale, scale, scale);
        rot := make_rotation_matrix4(q);
        if extra_rot != 0 {
            extra_q: Quaternion;
            set_from_axis_and_angle(*extra_q, 0.0, 0.5, 0.5, extra_rot);
            rot *= make_rotation_matrix4(extra_q);
        }

        return translation * scl * rot;
    }

    // render player
    if !game.player_has_crashed && (game.player.hurt_cooldown <= 0 || (game.rendered_frame_count & 1)) {
        model := game.snake_head;
        model.meshes[0].material.diffuse = make_vector3(0.5, 0.5, 1.0);

        curve :: (x: float) -> float { return 1.0 / pow(x, 0.2) * 0.5 + 0.5; }

        player_scale := max(1.0, curve(game.player.time_since_last_fire));
        model.meshes[0].model_matrix = actor_model_matrix(*game.player, scale=player_scale, extra_rot=game.player.walk_rotate);
        defer model.meshes[0].model_matrix = matrix4_identity();
        render_model(model);
    }

    // render enemies
    for * game.enemies {
        if it.state != Enemy_State.SPAWNING || (game.rendered_frame_count & 1) {
            model := game.snake_head;
            model.meshes[0].model_matrix = actor_model_matrix(it);//, .36);
            model.meshes[0].material.diffuse = make_vector3(1.0, 0.2, 0.1);
            model.meshes[0].model_matrix = actor_model_matrix(it);//, .36);
            defer model.meshes[0].model_matrix = matrix4_identity();
            render_model(model);
        }
    }

    // render bullets
    {
        model := game.fruit;
        model.meshes[0].material.diffuse = make_vector3(1.0, 0.0, 0.0);
        for * game.bullets {
            translation := make_translation_matrix4(make_vector3(it.pos.x + game.grid_offset_x + bias, bias, it.pos.y + game.grid_offset_y + bias));
            scale_val := game.settings.visual_bullet_size;
            model.meshes[0].model_matrix = translation * make_scale_matrix(scale_val, scale_val, scale_val);
            defer model.meshes[0].model_matrix = matrix4_identity();
            render_model(model);
        }
    }

    // render debug AABB
    if false {
        glDisable(GL_DEPTH_TEST);
        defer glEnable(GL_DEPTH_TEST);

        render_aabb :: inline (it: *AABB) {
            p1 := it.pos - it.extents;
            p2 := it.pos + it.extents;
            color := make_vector4(1.0, 1.0, 1.0, 1.0);

            w := it.extents.x * 2;
            h := it.extents.y * 2;

            draw_line(make_Quad(p1.x + game.grid_offset_x, p1.y + game.grid_offset_y, w, 0), color);
            draw_line(make_Quad(p1.x + game.grid_offset_x, p2.y + game.grid_offset_y, w, 0), color);

            draw_line(make_Quad(p1.x + game.grid_offset_x, p1.y + game.grid_offset_y, 0, h), color);
            draw_line(make_Quad(p2.x + game.grid_offset_x, p1.y + game.grid_offset_y, 0, h), color);
        }

        using game;
        for * static render_aabb(it);
        for * bullets render_aabb(it);
        for * enemies render_aabb(it);
        render_aabb(*player);
    }

    // UI

    glDisable(GL_DEPTH_TEST);
    proj := game.projection;
    defer game.projection = proj;

    game.view = matrix4_identity();
    game.projection = orthographic_projection_matrix(0, cast(float) game.window_width, 0, cast(float) game.window_height, -1, 1);

    white := make_vector4(1, 1, 1, 1);

    {
        base := game.window_height - FONT_HEIGHT;
        text := tprint("Defeated: % - Health: %", game.stats.num_enemies_defeated, game.player.health);
        color := white;
        offset := 0;
        draw_text(game.font, color, offset, base, text);
    }

    {
        base := game.window_height - FONT_HEIGHT;
        text := game.fps_string;
        color := white;
        offset := game.window_width - 300;
        draw_text(game.font, color, offset, base, text);
    }

    if game.player_has_crashed {
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        draw_quad(make_Quad(0, 0, cast(float) game.window_width, cast(float) game.window_height), make_vector4(0.9, 0.2, 0.2, 0.6));
        glDisable(GL_BLEND);

        white := make_vector4(1, 1, 1, 1);

        base := game.window_height - 164;

        GAME_OVER_TEXT :: "Game Ovah. You got % points. Press '%' to play again!";
        {
            button_or_key_name := "";
            if gamepad.connected {
                button_or_key_name = "A";
            } else {
                button_or_key_name = "Enter";
            }

            color := white;
            offset := game.window_width / 2  - get_string_width_in_pixels(game.font, GAME_OVER_TEXT) / 2;
            draw_text(game.font, color, offset, game.window_height / 2 + FONT_HEIGHT / 2, GAME_OVER_TEXT, game.stats.num_enemies_defeated, button_or_key_name);
        }
    }
}


render_light_shadowmap :: (using light: *Light) {
    if !shadow_map.id {
        shadow_map = make_framebuffer(game.shadow_map_size, game.shadow_map_size, msaa=false, color=false, depth=true);
    }

    use_frame_buffer(*shadow_map);
    old_projection := game.projection;
    old_view := game.view;

    defer game.projection = old_projection;
    defer game.view = old_view;

    SCENE_SIZE: float = cast(float) game.grid_size*2;
    game.projection = orthographic_projection_matrix(-SCENE_SIZE, SCENE_SIZE, -SCENE_SIZE, SCENE_SIZE, -200, 200);


    FORWARD := make_vector3(0, 0, -1);
    axis := cross(FORWARD, direction);
    angle := dot(FORWARD, direction);

    q: Quaternion;
    set_from_axis_and_angle(*q, axis.x, axis.y, axis.z, -angle);
    game.view = make_rotation_matrix4(q);

    projection_view_matrix = game.projection * game.view;
    render_game();
}

draw_text_centered :: (color: Vector4, y: s32, text: string) {
    x := game.window_width / 2  - get_string_width_in_pixels(game.font, text) / 2;
    draw_text(game.font, color, xx x, xx y, text);
}

render_menu :: () {
    proj := game.projection;
    defer game.projection = proj;
    view := game.view;
    defer game.view = view;

    game.view = matrix4_identity();

    game.projection = orthographic_projection_matrix(0, cast(float) game.window_width, 0, cast(float) game.window_height, -1, 1);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    draw_quad(make_Quad(0, 0, cast(float) game.window_width, cast(float) game.window_height), make_vector4(0.2, 0.2, 0.2, 0.5));
    glDisable(GL_BLEND);

    yellow := make_vector4(1, 1, 0, 1);
    white  := make_vector4(1, 1, 1, 1);

    base := game.window_height - 330 + 64;

    using Menu_Selection;


    {
        color := white;
        if game.menu_selection == CONTINUE_GAME then color = yellow;
        draw_text_centered(color, xx base, "Continue");
    }
    base -= 64;
    {
        color := white;
        if game.menu_selection == RESET_GAME then color = yellow;
        draw_text_centered(color, base, "Reset Game");
    }
    base -= 64;
    {
        color := white;
        if game.menu_selection == QUIT then color = yellow;
        draw_text_centered(color, base, "Quit");
    }
}

render :: () {
    for game.lights render_light_shadowmap(it);

    if game.msaa glEnable(GL_MULTISAMPLE);
    defer if game.msaa glDisable(GL_MULTISAMPLE);

    use_frame_buffer(*game.game_framebuffer);
    render_game();
    if game.mode == game.mode.MENU then render_menu();
    use_frame_buffer(null);

    proj := game.projection;
    defer game.projection = proj;
    view := game.view;
    defer game.view = view;

    game.view = matrix4_identity();

    game.projection = orthographic_projection_matrix(0, 1, 0, 1, -1, 1);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    // draw_textured_quad(make_Quad(0, 0, 1, 1), game.game_framebuffer.color_texture);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    fb := game.game_framebuffer;
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fb.id);

    window_fb_width, window_fb_height := get_framebuffer_dimensions(null);
    glBlitFramebuffer(0, 0, fb.width, fb.height, 0, 0, window_fb_width, window_fb_height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glFlush();

    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    #if DEBUG_UI ImGui.Render();
}

damage_player :: (player: *Player) {
    player.health -= 1;
    if player.health <= 0 {
        game.player_has_crashed = true;
    }

    play_sound(game.hit_wall_sound, true);
    game.screen_shake_percent = game.settings.player.hurt_screenshake;
    player.hurt_cooldown = game.settings.player.hurt_cooldown;

}

move_actor :: (using actor: *Actor, delta: Vector2) {
    if delta.x != 0 || delta.y != 0 {
        try_move(actor, delta, game.static);

        dir := delta;
        normalize_vec2(*dir);
        look_direction = dir;
    }
}

update_game :: (dt: float) {
    using game;

    if game.player_has_crashed {
        if enter_pressed reset_game();
    }

    // update player
    game.player.time_since_last_fire += dt;
    if !game.player_has_crashed {
        move_delta : Vector2;
        for vec, idx: direction_vectors if input_direction[idx]
            move_delta += vec;
        normalize_vec2(*move_delta);

        move_actor(*player, move_delta * settings.player.speed * dt);

        if move_delta.x != 0 || move_delta.y != 0 {
            SPD :: 20.0;
            if player.walk_dir > 0
                player.walk_rotate += dt * SPD;
            else
                player.walk_rotate -= dt * SPD;

            if abs(player.walk_rotate) > TAU / 4.0
                player.walk_dir *= -1;
        } else {
            player.walk_rotate = 0;
        }

        // check collision against enemies
        if timer_done(dt, *player.hurt_cooldown) {
            for * enemies {
                if it.state != Enemy_State.SPAWNING && overlaps(it, *player) {
                    damage_player(*player);
                    break;
                }
            }
        }

        if player.hurt_cooldown <= 0 && timer_done(dt, *fire_time_cooldown) {
            fire_vector: Vector2;
            for vec, idx: direction_vectors if firing_in_direction[idx]
                fire_vector += vec;

            if is_nonzero(fire_vector) {
                normalize_vec2(*fire_vector);
                fire_time_cooldown = settings.player.fire_rate;
                play_sound(game.arrow_sound, perturb=true, volume=0.2);

                using bullet: Bullet;
                bullet.extents.x = settings.bullet_size;
                bullet.extents.y = settings.bullet_size;
                player.time_since_last_fire = 0;
                pos = player.pos;
                vel = fire_vector * settings.player.bullet_speed + move_delta * settings.player.move_speed_add_to_bullet;
                array_add(*bullets, bullet);
            }
        }
    }

    // enemy "AI"
    determine_next_state :: inline (using enemy: *Enemy) {
        using Enemy_State;

        roll := random_get_zero_to_one();
        if #complete state == {
            case SPAWNING;
                if roll < .5 || game.player_has_crashed state = FIRING;
                else state = CHASING_PLAYER;
            case CHASING_PLAYER;
                if roll < .3 state = FIRING;
                else state = WAITING;
            case WAITING;
                if roll < .3 || game.player_has_crashed state = FIRING;
                else state = CHASING_PLAYER;
            case FIRING;
                if roll < .3 && !game.player_has_crashed state = CHASING_PLAYER;
                else state = WAITING;
        }
    }

    advance_to_next_state :: inline (using enemy: *Enemy) {
        using Enemy_State;

        determine_next_state(enemy);
        if state == {
            case SPAWNING;       timer = random_get_within_range(1, 1.2);
            case CHASING_PLAYER; timer = random_get_within_range(1, 3);
            case WAITING;        timer = random_get_within_range(2, 4);
            case FIRING;
                timer = random_get_within_range(3, 4);
                shoot_angle = random_get_zero_to_one() * TAU;
        }
    }

    // update enemies
    for * enemies {
        using it;
        if timer_done(dt, *timer) {
            advance_to_next_state(it);
            continue;
        }

        using Enemy_State;
        if #complete state == {
            case WAITING;
            case SPAWNING;
            case FIRING;
                shoot_angle += settings.enemy.shoot_angle_speed * dt;
                fire_vector := unit_vector(make_vector3(cos(shoot_angle), sin(shoot_angle), 0));
                look_direction = fire_vector.xy;
                if timer_done(dt, *shoot_cooldown, settings.enemy.fire_rate) {
                    play_sound(game.arrow_sound, perturb=true, volume=0.2);
                    bullet: Bullet;
                    bullet.pos = pos;
                    bullet.extents.x = settings.bullet_size;
                    bullet.extents.y = settings.bullet_size;
                    bullet.vel = fire_vector.xy * settings.enemy.bullet_speed;
                    bullet.friendly = false;
                    array_add(*bullets, bullet);
                }
            case CHASING_PLAYER;
                to_player := game.player.pos - pos;
                normalize_vec2(*to_player);
                move_actor(it, settings.enemy.move_speed * to_player * dt);
        }

    }

    // spawn new enemies
    if enemies.count < settings.enemy.max_count {
        next_spawn_time := random_get_within_range(settings.enemy.spawn_delay_min, settings.enemy.spawn_delay_max);
        if timer_done(dt, *enemy_spawn_cooldown, next_spawn_time) {
            for 0..(cast(int)(random_get_zero_to_one() * settings.enemy.spawn_at_a_time + 1) - 1)
                spawn_new_enemy();
        }
    }

    // kill old bullets
    for *bullet: bullets {
        bullet.life_timer -= dt;
        if bullet.life_timer <= 0 {
            remove bullet;
            continue;
        }
    }

    // update bullets
    for *bullet: bullets {
        bullet.pos += bullet.vel * dt;

        if bullet.friendly {
            for *enemy: enemies {
                if enemy.state != Enemy_State.SPAWNING && overlaps(bullet, enemy) {
                    remove enemy;
                    game.stats.num_enemies_defeated += 1;
                    settings.enemy.spawn_at_a_time += 0.5;
                    play_sound(game.hit_wall_sound, true);
                    game.screen_shake_percent = 0.85;
                    remove bullet;
                    break;
                }
            }
        } else {
            if !game.player_has_crashed && overlaps(bullet, *player) {
                damage_player(*player);
                remove bullet;
                continue;
            }
        }

        for * static if overlaps(bullet, it) {
            remove bullet;
            break;
        }
    }
}

update_menu :: (dt: float) {
    using game;

    if up_pressed && menu_selection > 0
        menu_selection -= cast(Menu_Selection)1;

    if down_pressed && menu_selection < xx Menu_Selection_MAX
        menu_selection += cast(Menu_Selection)1;

    if enter_pressed {
        using Menu_Selection;
        if #complete menu_selection == {
            case CONTINUE_GAME; mode = mode.GAME;
            case RESET_GAME; reset_game();
            case QUIT; game.quit = true;
        }
    }
}

update :: (dt: float) {
    using game;

    #if DEBUG_UI {
        lights[0].radiance = settings.sun_light.radiance;
        lights[0].direction = settings.sun_light.direction;
    }
    
    if #complete mode == {
        case mode.GAME; update_game(dt * time_scale);
        case mode.MENU; update_menu(dt);
    }

    // Update the screen shake regardless of game mode, otherwise
    // we'll get infinte shaking while the game is paused.
    if screen_shake_percent < 1.0 {
        screen_shake_percent += (screen_shake_step * dt);
        if screen_shake_percent > 1.0 screen_shake_percent = 1.0;
    }
}

play_sound :: (data: *Mixer_Sound_Data, perturb: bool = true, volume := 0.7) -> *Sound_Stream {
    stream := make_stream(game.sound_player, data);
    assert(stream != null);

    if stream {
        stream.sound_data = data;
        num_source_samples: s64 = data.nsamples_times_nchannels / data.nchannels;
        stream.repeat_end_position = num_source_samples;
        stream.user_volume_scale = volume;
    }

    if perturb && stream {
        stream.user_volume_scale = random_get_within_range(volume, volume + 0.2);
        stream.desired_rate = random_get_within_range(0.7, 1.22);
    }
    
    return stream;
}

spawn_new_enemy :: () {
    enemy: Enemy;

    enemy.extents = make_vector2(game.settings.enemy.size, game.settings.enemy.size);

    enemy.pos.x = random_get_within_range(0, PLAY_AREA_SIZE - 1);
    enemy.pos.y = random_get_within_range(0, PLAY_AREA_SIZE - 1);

    enemy.state = Enemy_State.SPAWNING;
    enemy.timer = random_get_within_range(1.0, 2.0);

    array_add(*game.enemies, enemy);
}

reset_game :: () {
    game.stats.num_enemies_defeated = 0;

    // setup player
    {
        using game.player;
        pos = make_vector2(PLAY_AREA_SIZE / 2, PLAY_AREA_SIZE / 2);
        extents.x = game.settings.player.size;
        extents.y = game.settings.player.size;
        health = STARTING_HEALTH;
    }

    // setup enemies
    {
        array_reset(*game.enemies);
        for 0..game.settings.enemy.initial_spawn_count-1
            spawn_new_enemy();
    }

    array_reset(*game.bullets);

    // setup collision
    {
        array_reset(*game.static);

        make_static_collider :: (x: float, y: float, extents_x: float, extents_y: float) -> AABB {
            box: AABB;
            box.pos = make_vector2(x, y);
            box.extents = make_vector2(extents_x, extents_y);
            return box;
        }
        
        half_grid_size := cast(float)PLAY_AREA_SIZE * .5;

        // add colliders for the walls
        array_add(*game.static,
            make_static_collider(-1, half_grid_size, 1, half_grid_size + 2),
            make_static_collider(half_grid_size, -1, half_grid_size + 2, 1),
            make_static_collider(PLAY_AREA_SIZE, half_grid_size, 1, half_grid_size + 2),
            make_static_collider(half_grid_size, PLAY_AREA_SIZE, half_grid_size + 2, 1));
    }

    using game;
    
    mode = game.mode.GAME;

    down_pressed = false;
    up_pressed = false;
    left_pressed = false;
    right_pressed = false;
    enter_pressed = false;

    menu_selection = Menu_Selection.CONTINUE_GAME;

    player_has_crashed = false;
    screen_shake_percent = 1;
}


get_model_by_tag :: (models: [] *Model, tag: string) -> *Model {
    for models if it.tag == tag return it;

    return null;
}

load_audio_file :: (name: string) -> *Mixer_Sound_Data {
    data : *Mixer_Sound_Data = null;

    file_data, success := read_entire_file(name);
    if !success return data;

    data = New(Mixer_Sound_Data);
    data.name = copy_string(name);
    data.buffer = file_data;
    data.type = Mixer_Sound_Data.Type.OGG_COMPRESSED;
    return data;
}

back_buffer: *Texture;
window_handle: *void; // @Hack

do_screenshot :: () {
    fb := game.game_framebuffer;

    tex: Texture;
    tex.width = fb.width;
    tex.height = fb.height;
    tex.depth = 1;
    tex.mipmap_count = 1;
    tex.format = Texture_Format.RGBA8;
    tex.flags |= Texture_Flags.Render_Target;
    tex.gl_handle = fb.color_texture;
    if fb.msaa tex.gl_target = GL_TEXTURE_2D_MULTISAMPLE;
    else       tex.gl_target = GL_TEXTURE_2D;
    tex.gl_internal_format = GL_RGBA8;
    bitmap := get_bitmap_from_texture(*tex, Texture_Format.RGB8, fb.width, fb.height, srgb=false);
    
    Clipboard :: #import "Clipboard";
    Clipboard.os_clipboard_set_bitmap(bitmap.width, bitmap.height, bitmap.data);

    print("Screenshot copied to clipboard.\n");
}

debug_callback :: (source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: *u8, userParam: *void) #c_call {
    pctx := cast(*Context) userParam;
    ctx := <<pctx;
    push_context ctx {
        #if OS_WINDOWS {
            // print("source: %\n", source);
            // print("type: %\n", type);
            // print("id: %\n", id);
            // print("severity: %\n", severity);
            // print("length: %\n", length);
            // print("message: %\n", message);
            // print("userParam: %\n", userParam);
            if type == GL_DEBUG_TYPE_ERROR print("GL Error:%\n", to_string(message));
        }
    }
}


init_game :: () {
    context.logger = (message: string, ident: string, mode: Log_Mode, data: *void) {
        print("[%] %", ident, message);
    };

    {
        found, exe_path, exe_name := split_by_character_from_right(get_path_of_running_executable(), #char "/");
        if !found {
            print("Error: unable to find my own exe\n");
            return;
        }
        parse_config_file(*game.settings, tprint("%/%", exe_path, "shooter.cfg"));
    }

    direction_vectors[Direction.UP]    = make_vector2(0, -1);
    direction_vectors[Direction.DOWN]  = make_vector2(0, 1);
    direction_vectors[Direction.LEFT]  = make_vector2(-1, 0);
    direction_vectors[Direction.RIGHT] = make_vector2(1, 0);

    Pool.set_allocators(*game.pool);

    init_gamepad();

    if running_at_compile_time() {
        set_working_directory(sprint("%1%2", #filepath, "../run_tree"));
    } else {
        #if OS_MACOSX {
            bundle_dir := osx_get_bundle_resources_directory();
            print("Bundle Resource Directory: %\n", bundle_dir);
            set_working_directory(bundle_dir);
        } else {
            set_working_directory(path_strip_filename(get_path_of_running_executable()));
        }

        args := get_command_line_arguments();
        defer array_reset(*args);
        for args if it == {
            case "no_msaa"; game.msaa = false;
            case "low";     game.shadow_map_size = LOW_SHADOW_MAP_SIZE;
            case "medium";  game.shadow_map_size = MEDIUM_SHADOW_MAP_SIZE;
            case "high";    game.shadow_map_size = HIGH_SHADOW_MAP_SIZE;
        }
    }
}

load_resources :: () {
    game.arrow_sound = load_audio_file("data/arrow.ogg");
    game.eat_sound = load_audio_file("data/eat_01.ogg");
    game.hit_wall_sound = load_audio_file("data/Jump_1.ogg");
    game.hurt_sound = load_audio_file("data/hurt.ogg");

    game.ambience = load_audio_file("data/bgm.ogg");

    {
        vert := read_entire_file("data/shaders/textured_quad.vert");
        frag := read_entire_file("data/shaders/textured_quad.frag");
        untext_frag := read_entire_file("data/shaders/untextured_quad.frag");
        
        defer free(vert);
        defer free(frag);
        defer free(untext_frag);
        
        game.textured_quad_shader = compile_shader_source(vert, frag);
        game.untextured_quad_shader = compile_shader_source(vert, untext_frag);
    }

    bytes_loaded: s64;
    game.font, bytes_loaded = load_font("data", "YanoneKaffeesatz-Regular.otf", FONT_HEIGHT);

    game.snake_head = load_obj("data/head.obj")[0];
    fruit_objs := load_obj("data/apple.obj");
    game.fruit = get_model_by_tag(fruit_objs, "Fruit_Body");

    wall_model := load_obj("data/wall.obj")[0];
    game.wall = generate_wall_model_from_tile(wall_model);

    game.tree = load_obj("data/tree.obj");

    floor_tile := load_obj("data/generic_floor_tile.obj")[0];
    game.generic_floor_tile = generate_floor_model_from_tile(floor_tile, cast(s32) game.grid_size);

    buffer_model(game.snake_head);
    buffer_model(game.fruit);

    buffer_model(game.wall);
    for game.tree buffer_model(it);
    buffer_model(game.generic_floor_tile);
}

fini_game :: () {
    shutdown(game.sound_player);
    free(game.sound_player);
    Pool.release(*game.pool);
}

do_frame :: (window: Window_Type) -> did_render_frame: bool {
    was_resized, record := is_a_window_resized();
    if was_resized {
        width, height := record.width, record.height;
        game.window_width = width;
        game.window_height = height;

        print("RESIZE width, height: % , %\n", width, height);

        fb_width, fb_height := get_framebuffer_dimensions(null);
        resize_buffer(*game.game_framebuffer, fb_width, fb_height);
    }

    width := game.window_width;
    height := game.window_height;
    // print("width, height: % , %\n", width, height);
    // glViewport(0, 0, cast(u32) width, cast(u32) height);
    
    aspect := cast(float) width / cast(float) height;
    FOV_DEGREES :: 90.0;
    game.projection = make_projection_matrix((TAU / 360.0) * FOV_DEGREES, aspect, 0.1, 1000.0, x_offset=0, y_offset=0);
    q: Quaternion;
    set_from_axis_and_angle(*q, 1.0, 0.0, 0.0, (PI/2) - (PI/20));
    game.view = make_rotation_matrix4(q) * make_translation_matrix4(-game.settings.camera.pos);
    game.grid_offset_x = -(cast(float) game.grid_size / 2);
    game.grid_offset_y = -(cast(float) game.grid_size / 2);

    for events_this_frame {
        #if DEBUG_UI ImGui_Impl_ProcessEvent(it);

        using game;
        if it.type == {
            case Event_Type.QUIT;
                quit = true;
            case Event_Type.KEYBOARD;
                key_down := it.key_pressed != 0;
                if it.key_code == {
                    case Key_Code.F8;
                        do_screenshot();

                    case cast(Key_Code)(#char "P");
                        if key_down { if time_scale > 0 time_scale = 0; else time_scale = 1; }

                    //case cast(Key_Code)(#char "R"); if key_down reset_game();

                    case cast(Key_Code)(#char "W"); input_direction[Direction.UP]    = key_down;
                    case cast(Key_Code)(#char "A"); input_direction[Direction.LEFT]  = key_down;
                    case cast(Key_Code)(#char "S"); input_direction[Direction.DOWN]  = key_down;
                    case cast(Key_Code)(#char "D"); input_direction[Direction.RIGHT] = key_down;

                    case cast(Key_Code)(#char "I"); firing_in_direction[Direction.UP]    = key_down;
                    case cast(Key_Code)(#char "J"); firing_in_direction[Direction.LEFT]  = key_down;
                    case cast(Key_Code)(#char "K"); firing_in_direction[Direction.DOWN]  = key_down;
                    case cast(Key_Code)(#char "L"); firing_in_direction[Direction.RIGHT] = key_down;

                    case cast(Key_Code)(#char "`"); if key_down show_inspector = !show_inspector;

                    case Key_Code.ARROW_UP;
                        up_pressed = key_down;
                        firing_in_direction[Direction.UP] = key_down;
                    case Key_Code.ARROW_DOWN;
                        down_pressed = key_down;
                        firing_in_direction[Direction.DOWN] = key_down;
                    case Key_Code.ARROW_LEFT;
                        left_pressed = key_down;
                        firing_in_direction[Direction.LEFT] = key_down;
                    case Key_Code.ARROW_RIGHT;
                        right_pressed = key_down;
                        firing_in_direction[Direction.RIGHT] = key_down;
                    case Key_Code.ENTER;
                        if key_down {
                            if it.alt_pressed then {
                                toggle_fullscreen(window, !fullscreen, *saved_window_info);
                                fullscreen = !fullscreen;
                            } else {
                                enter_pressed = true;
                            }
                        }
                    case cast(Key_Code)(#char "Q");
                        if key_down && it.shift_pressed quit = true;
                    case Key_Code.ESCAPE;
                        if it.key_pressed == 1 {
                            if mode == mode.GAME then mode = mode.MENU;
                            else if mode == mode.MENU then mode = mode.GAME;
                        }
                }
        }
    }

    if gamepad.connected {
        if gamepad.buttons[Gamepad_Code.START] & Key_Current_State.START {
            if game.mode == game.mode.GAME then game.mode = game.mode.MENU;
            else if game.mode == game.mode.MENU then game.mode = game.mode.GAME;
        }
        if gamepad.buttons[Gamepad_Code.DPAD_UP] & Key_Current_State.START
            game.up_pressed = true;
        if gamepad.buttons[Gamepad_Code.DPAD_DOWN] & Key_Current_State.START
            game.down_pressed = true;
        if gamepad.buttons[Gamepad_Code.DPAD_LEFT] & Key_Current_State.START
            game.left_pressed = true;
        if gamepad.buttons[Gamepad_Code.DPAD_RIGHT] & Key_Current_State.START
            game.right_pressed = true;
        if gamepad.buttons[Gamepad_Code.A] & Key_Current_State.START
            game.enter_pressed = true;
        if gamepad.buttons[Gamepad_Code.B] & Key_Current_State.START
            if game.mode == game.mode.MENU then game.mode = game.mode.GAME;
    }

    #if DEBUG_UI new_imgui_frame(window);

    dt: float;
    now := get_time();
    if game.last_time dt = cast(float) (now - game.last_time);
    game.last_time = now;
    
    game.elapsed_time += dt;
    game.fps_time += dt;
    game.gamepad_time += dt;
    
    TICK_PERIOD: float64 : 1.0/60.0; // time between game updates
    need_to_render := false;
    while game.elapsed_time >= TICK_PERIOD {
        game.elapsed_time -= TICK_PERIOD;
        need_to_render = true;
        update(xx TICK_PERIOD);

        game.down_pressed = false;
        game.up_pressed = false;
        game.left_pressed = false;
        game.right_pressed = false;
        game.enter_pressed = false;
    }

    pre_entity_update(game.sound_player);
    for game.sound_player.streams  it.marked = true;
    post_entity_update(game.sound_player, dt);
    
    if need_to_render {
        game.FPS += 1;
        game.rendered_frame_count += 1;
        render();
    }

    if game.fps_time >= 1.0 {
        free(game.fps_string);
        game.fps_string = sprint("FPS: %", game.FPS);
        game.fps_time -= 1.0;
        game.FPS = 0;
    }

    GAMEPAD_SCAN_TICK_PERIOD :: 5.0;
    if game.gamepad_time > GAMEPAD_SCAN_TICK_PERIOD {
        game.gamepad_time -= GAMEPAD_SCAN_TICK_PERIOD;
        init_gamepad();
    }

    Pool.reset(*game.pool);

    return need_to_render;
}

show_inspector: bool;
#if DEBUG_UI {
new_imgui_frame :: (window: *void) {
    ImGui_Impl_NewFrame(window, game.window_width, game.window_height);
    if show_inspector {
        inspect("settings", *game.settings);
    }
}
}

// @Note see macosx.jai for the MacOSX entry point that uses Cocoa/AppKit's run loop.
main :: () {
    init_game();

    DEFAULT_WIN_WIDTH :: 1280;
    DEFAULT_WIN_HEIGHT :: 720;

    window := create_window(DEFAULT_WIN_WIDTH, DEFAULT_WIN_HEIGHT, "Shooter");
    window_handle = xx window;
    gl_create_context(window, 3, 2);
    gl_load(*gl);

    if GL_VERSION_4_3 {
        glDebugMessageCallback(debug_callback, *context);
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
    } else if GL_ARB_debug_output {
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
        glDebugMessageCallbackARB(debug_callback, *context);
    }

    #if DEBUG_UI {
        ImGui_Impl_Init(window);
        ImGui.StyleColorsLight();
    }

    {
        using game;
        window_width = DEFAULT_WIN_HEIGHT;
        window_height = DEFAULT_WIN_HEIGHT;

        sound_player = New(Sound_Player);
        sound_player.update_history = true;
        if settings.mute_all_sounds
            set_master_volume(sound_player, 0);

        success := init(sound_player, window, true, true);
        assert(success);

        load_resources();

        stream := play_sound(ambience, false);
        stream.flags |= stream.REPEATING;
        stream.user_volume_scale = 0.5;
    
        view = matrix4_identity();
    
        reset_game();

        vao: u32;
        glGenVertexArrays(1, *vao);
        glBindVertexArray(vao);

        glGenBuffers(1, *immediate_draw_buffer_id);

        game_framebuffer = make_framebuffer(DEFAULT_WIN_WIDTH, DEFAULT_WIN_HEIGHT, msaa=game.msaa);
        fb_width, fb_height := get_framebuffer_dimensions(null);
        resize_buffer(*game_framebuffer, fb_width, fb_height);

        light := new_Light();
        light.radiance = settings.sun_light.radiance;
        light.direction = settings.sun_light.direction;
        array_add(*lights, light);
    }

    #if OS_MACOSX {
        Objective_C :: #import "Objective_C";
        #import "Objective_C/LightweightRenderingView";

        view := Objective_C.NSWindow.contentView(window);
        glview := cast(*LightweightOpenGLView) view;

        value: s32 = 1;
        Objective_C.NSOpenGLContext.setValues(glview.glContext(glview), *value, Objective_C.NSOpenGLContextParameterSwapInterval);
    }

    while true {
        update_window_events();
        update_gamepad();
        reset_temporary_storage();
        
        if game.quit break;
        
        if do_frame(window) swap_buffers(window);
    }

    fini_game();
}
