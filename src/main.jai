
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

#load "render.jai";
#load "obj_loader.jai";
#load "util.jai";

#if OS_WINDOWS {
DEBUG_UI :: true; 
} else {
DEBUG_UI :: false; // TODO: implement some of the imgui input bits for non windows platforms (Input module doesn't have mouse move events)
}

#if DEBUG_UI {
#load "imgui_inspector.jai";
}

#if OS_MACOSX {
    #load "macosx.jai"; // Cocoa app stuff/entry point
}

// Game constants
ENEMY_SIZE :: 0.45;
ENEMY_FIRE_RATE :: 0.3;
ENEMY_MOVE_SPEED :: 3.5;
ENEMY_BULLET_SPEED :: 5.0;
ENEMY_SHOOT_ANGLE_SPEED :: PI * .4;
ENEMY_SPAWN_DELAY_MIN :: 0.6;
ENEMY_SPAWN_DELAY_MAX :: 2.3;
ENEMY_MAX_COUNT :: 6;
ENEMY_SPAWN_AT_A_TIME :: 2;

PLAYER_SPEED :: 9.0;
PLAYER_HURT_COOLDOWN :: 1.0;
PLAYER_BULLET_SPEED :: 15.0;
PLAYER_FIRE_RATE :: 0.15;
PLAYER_MOVE_SPEED_ADD_TO_BULLET :: 3;

BULLET_SIZE :: 0.25;

Direction :: enum { UP; DOWN; LEFT; RIGHT; }
direction_vectors: [4]Vector2;

AABB :: struct {
    pos: Vector2;
    extents: Vector2;
}

overlaps :: (a: *AABB, b: *AABB) -> bool {
    t := b.pos - a.pos;
    return abs(t.x) <= (a.extents.x + b.extents.x) &&
        abs(t.y) <= (a.extents.y + b.extents.y);
}

Bullet :: struct {
    using aabb: AABB;
    vel: Vector2;
    life_timer: float = 4;
    friendly: bool = true; // fired by player

    extents.x = BULLET_SIZE;
    extents.y = BULLET_SIZE;
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

    extents.x = ENEMY_SIZE;
    extents.y = ENEMY_SIZE;

    state: Enemy_State;
    timer: float;

    shoot_cooldown: float;
    shoot_angle: float;
}

Player :: struct {
    using actor: Actor;
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

MENU_SELECTION_CONTINUE_GAME :: 0;
MENU_SELECTION_RESET_GAME    :: 1;
MENU_SELECTION_QUIT          :: 2;
MAX_MENU_SELECTION           :: 2;

FONT_HEIGHT :: 48;

LOW_SHADOW_MAP_SIZE    :: 512;
MEDIUM_SHADOW_MAP_SIZE :: 1024;
HIGH_SHADOW_MAP_SIZE   :: 2048;

game: struct {
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

    camera_position: Vector3;

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

    shadow_map_size: s32 = LOW_SHADOW_MAP_SIZE;

    msaa := true;
    
    projection: Matrix4;
    view: Matrix4; // conceptually the transform of the camera from (0,0,0), the shader will invert this

    mode: enum {
        GAME;
        MENU;
    };

    menu_selection: int;
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

    snake_move_percent := 0.0;
    snake_move_step := 4.0;

    snake_dir_x: int;
    snake_dir_y: int;
    can_move := false;
    
    snake_head: *Model;
    snake_head_mid: *Model;
    snake_body_straight: *Model;
    snake_body_angle: *Model;
    snake_tail: *Model;
    fruit: *Model;
    fruit_leaf: *Model;
    wall: *Model;
    tree: [] *Model;
    generic_floor_tile: *Model;

    grid_size: u32 = INITIAL_GRID_SIZE; // width and height of the grid
    grid_offset_x: float;
    grid_offset_y: float;
    grid: [..] Occupant; // grid.count == grid_size * grid_size;
    
    snake: [..] struct {
        x: int;
        y: int;
    }; // coords into grid where snake parts are, index := x + y * current(grid_size); 0th = head, count-1 = tail

    player: Player;
    bullets: [..]Bullet;
    enemies: [..]Enemy;
    enemy_spawn_cooldown: float;

    // birds animation state
    bird_models: [3] *Model;
    bird_anim_percent := 0.0;
    bird_anim_step := 6.0;
    bird_rotation := 0.0;
    bird_rotation_step := 5.0;

    screen_shake_percent := 1.0;
    screen_shake_step := 2.1;
    shake_amount := 1.0;

    snake_failed_on_turn := false;
    snake_head_x_scale := 1.0;

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

    { // East wall
        model := tile;

        for y: 0..game.grid_size-1 {
            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size + 1,  0, y + game.grid_offset_y));
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size + 1,  0, y + game.grid_offset_y + 0.5));
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size + 1,  0, game.grid_offset_y + game.grid_size));
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
                it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x-1,  0, y + game.grid_offset_y + 0.5)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x-1,  0, y + game.grid_offset_y + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x-1,  0, game.grid_offset_y)) * rot;
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
                it.model_matrix = make_translation_matrix4(make_vector3(x + game.grid_offset_x + 0.5,  0, game.grid_offset_y-1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_vector3(x + game.grid_offset_x + 1,  0, game.grid_offset_y-1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x,  0, game.grid_offset_y-1)) * rot;
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
                it.model_matrix = make_translation_matrix4(make_vector3(x + game.grid_offset_x,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }

            for model.meshes {
                it.model_matrix = make_translation_matrix4(make_vector3(x + game.grid_offset_x + 0.5,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
                bake_and_concat_mesh(result.meshes[it_index], it);
            }
        }

        for model.meshes {
            it.model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size,  0, game.grid_offset_y + game.grid_size + 1)) * rot;
            bake_and_concat_mesh(result.meshes[it_index], it);
        }
    }

    return result;
}

ease_out_elastic :: (n: float) -> float {
    p := 0.3;
    return pow(2, -10*n) * sin((n-p/4.0) * TAU/p) + 1;
}

INITIAL_GRID_SIZE :: 11;
INITIAL_SNAKE_SIZE :: 5;
SMALLEST_SNAKE_SIZE :: 2; // always have a head and tail

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
        model_matrix := matrix4_identity();

        // for model {
            for model.meshes {
                it.model_matrix = model_matrix;
                render_mesh(it);
            }
        // }
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
            it.model_matrix = model_matrix;
            render_mesh(it);
        }
    }

    RENDER_TREES :: true;

    if RENDER_TREES {
    for x: -4..-1 {
        for y: -1..cast(s32) (game.grid_size/4 + 1) {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 2), 0, game.grid_offset_y + (y*4) - (x % 2)*2)); }
            for model: models for model.meshes render_mesh(it);
        }
    }

    for x: 1..4 {
        for y: -1..cast(s32) (game.grid_size/4 + 1) {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + game.grid_size + (x * 2), 0, game.grid_offset_y + (y*4) - (x % 2)*2)); }
            for model: models for model.meshes render_mesh(it);
        }
    }

    for x: 0..game.grid_size/4 {
        for y: -4..-1 {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 4) - (y % 2)*2, 0, game.grid_offset_y + (y*2))); }
            for model: models for model.meshes render_mesh(it);
        }
    }

    for x: 0..(game.grid_size/4)+1 {
        for y: 1..4 {
            models := game.tree;
            for model: models { model.meshes[0].model_matrix = make_translation_matrix4(make_vector3(game.grid_offset_x + (x * 4) - (y % 2)*2, 0, game.grid_offset_y + game.grid_size + (y*2))); }
            for model: models for model.meshes render_mesh(it);
        }
    }
    } // RENDER_TREES

    actor_model_matrix :: (using actor: *Actor, scale:float = 1) -> Matrix4 {
        translation := make_translation_matrix4(make_vector3(pos.x + game.grid_offset_x + bias, bias, pos.y + game.grid_offset_y + bias));

        q: Quaternion;
        set_from_axis_and_angle(*q, 0, 1, 0, TAU * .25 + angle_radians_vec2(look_direction));
        scl: Matrix4 = matrix4_identity();
        if scale != 1 scl = make_scale_matrix(scale, scale, scale);
        rot := make_rotation_matrix4(q);

        return translation * scl * rot;
    }

    // render player
    if game.player.hurt_cooldown <= 0 || (game.rendered_frame_count & 1) {
        model := game.snake_head;
        model.meshes[0].model_matrix = actor_model_matrix(*game.player);//, .36);
        defer model.meshes[0].model_matrix = matrix4_identity();
        for model.meshes render_mesh(it);
    }

    // render enemies
    for * game.enemies {
        if it.state != Enemy_State.SPAWNING || (game.rendered_frame_count & 1) {
            model := game.snake_head;
            model.meshes[0].model_matrix = actor_model_matrix(it);//, .36);
            defer model.meshes[0].model_matrix = matrix4_identity();
            for model.meshes render_mesh(it);
        }
    }

    // render bullets
    {
        model := game.fruit;
        model.meshes[0].material.diffuse = make_vector3(1.0, 0.0, 0.0);
        for * game.bullets {
            translation := make_translation_matrix4(make_vector3(it.pos.x + game.grid_offset_x + bias, bias, it.pos.y + game.grid_offset_y + bias));
            scale_val :: 0.5;
            model.meshes[0].model_matrix = translation * make_scale_matrix(scale_val, scale_val, scale_val);
            defer model.meshes[0].model_matrix = matrix4_identity();
            for model.meshes render_mesh(it);
        }
    }

    glDisable(GL_DEPTH_TEST);
    proj := game.projection;
    defer game.projection = proj;

    game.view = matrix4_identity();

    game.projection = orthographic_projection_matrix(0, cast(float) game.window_width, 0, cast(float) game.window_height, -1, 1);

    {
        white := make_vector4(1, 1, 1, 1);

        base := game.window_height - FONT_HEIGHT;

        APPLE_TEXT :: "Points: ";
        {
            text := tprint("%1%2", APPLE_TEXT, 0);
            color := white;
            offset := 0;
            draw_text(game.font, color, offset, base, text);
        }
    }

    {
        white := make_vector4(1, 1, 1, 1);

        base := game.window_height - FONT_HEIGHT;
        {
            text := game.fps_string;
            color := white;
            offset := game.window_width - 300;
            draw_text(game.font, color, offset, base, text);
        }
    }

    if game.player_has_crashed {
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        draw_quad(make_Quad(0, 0, cast(float) game.window_width, cast(float) game.window_height), make_vector4(0.2, 0.2, 0.2, 0.5));
        glDisable(GL_BLEND);

        white := make_vector4(1, 1, 1, 1);

        base := game.window_height - 164;

        GAME_OVER_TEXT :: "Game Over! Press '%' to play again!";
        {
            button_or_key_name := "";
            if gamepad.connected {
                button_or_key_name = "A";
            } else {
                button_or_key_name = "Enter";
            }

            color := white;
            offset := game.window_width / 2  - get_string_width_in_pixels(game.font, GAME_OVER_TEXT) / 2;
            draw_text(game.font, color, offset, game.window_height / 2 + FONT_HEIGHT / 2, GAME_OVER_TEXT, button_or_key_name);
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
    white := make_vector4(1, 1, 1, 1);

    base := game.window_height - 164;

    CONTINUE_GAME_TEXT :: "Continue";
    {
        color := white;
        if game.menu_selection == MENU_SELECTION_CONTINUE_GAME then color = yellow;
        offset := game.window_width / 2  - get_string_width_in_pixels(game.font, CONTINUE_GAME_TEXT) / 2;
        draw_text(game.font, color, offset, game.window_height - 164 + 64, CONTINUE_GAME_TEXT);
    }

    RESET_GAME_TEXT :: "Reset Game";
    {
        color := white;
        if game.menu_selection == MENU_SELECTION_RESET_GAME then color = yellow;
        offset := game.window_width / 2  - get_string_width_in_pixels(game.font, RESET_GAME_TEXT) / 2;
        draw_text(game.font, color, offset, game.window_height - 164, RESET_GAME_TEXT);
    }

    QUIT_GAME_TEXT :: "Quit";
    {
        color := white;
        if game.menu_selection == MENU_SELECTION_QUIT then color = yellow;
        offset := game.window_width / 2  - get_string_width_in_pixels(game.font, QUIT_GAME_TEXT) / 2;
        draw_text(game.font, color, offset, game.window_height - 164 - 64, QUIT_GAME_TEXT);
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

damage_player :: () {
    play_sound(game.hurt_sound, true);
    game.screen_shake_percent = 0.42;
    game.player.hurt_cooldown = PLAYER_HURT_COOLDOWN;
}

move_actor :: (using actor: *Actor, delta: Vector2) {
    pos += delta;
    if delta.x != 0 || delta.y != 0 {
        dir := delta;
        normalize_vec2(*dir);
        look_direction = dir;
    }
}

update_game :: (dt: float) {
    using game;

    if game.player_has_crashed {
        if enter_pressed {
            reset_game();
        }
    }

    turned := false;
    turned_right := true;

    // update player
    {
        move_delta : Vector2;
        for vec, idx: direction_vectors if input_direction[idx]
            move_delta += vec;
        normalize_vec2(*move_delta);

        move_actor(*player, move_delta * PLAYER_SPEED * dt);

        if timer_done(dt, *player.hurt_cooldown) {
            for * enemies {
                if overlaps(it, *player) {
                    damage_player();
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
                fire_time_cooldown = PLAYER_FIRE_RATE;
                play_sound(game.arrow_sound, perturb=true, volume=0.2);

                using bullet: Bullet;
                pos = player.pos;
                vel = fire_vector * PLAYER_BULLET_SPEED + move_delta * PLAYER_MOVE_SPEED_ADD_TO_BULLET;
                array_add(*bullets, bullet);
            }
        }
    }

    determine_next_state :: inline (using enemy: *Enemy) {
        using Enemy_State;

        roll := random_get_zero_to_one();
        if #complete state == {
            case SPAWNING;
                if roll < .5 state = FIRING;
                else state = CHASING_PLAYER;
            case CHASING_PLAYER;
                if roll < .3 state = FIRING;
                else state = WAITING;
            case WAITING;
                if roll < .3 state = FIRING;
                else state = CHASING_PLAYER;
            case FIRING;
                if roll < .3 state = CHASING_PLAYER;
                else state = WAITING;
        }
    }

    advance_to_next_state :: inline (using enemy: *Enemy) {
        using Enemy_State;

        determine_next_state(enemy);
        if state == {
            case SPAWNING;
                timer = random_get_within_range(1, 1.2);
            case CHASING_PLAYER;
                timer = random_get_within_range(1, 3);
            case WAITING;
                timer = random_get_within_range(2, 4);
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
                shoot_angle += ENEMY_SHOOT_ANGLE_SPEED * dt;
                fire_vector := unit_vector(make_vector3(cos(shoot_angle), sin(shoot_angle), 0));
                look_direction = fire_vector.xy;
                if timer_done(dt, *shoot_cooldown, ENEMY_FIRE_RATE) {
                    bullet: Bullet;
                    bullet.pos = pos;
                    bullet.vel = fire_vector.xy * ENEMY_BULLET_SPEED;
                    bullet.friendly = false;
                    array_add(*bullets, bullet);
                }
            case CHASING_PLAYER;
                to_player := game.player.pos - pos;
                normalize_vec2(*to_player);
                move_actor(it, ENEMY_MOVE_SPEED * to_player * dt);
        }

    }

    if enemies.count < ENEMY_MAX_COUNT {
        if timer_done(dt, *enemy_spawn_cooldown, random_get_within_range(ENEMY_SPAWN_DELAY_MIN, ENEMY_SPAWN_DELAY_MAX)) {
            for 0..(cast(int)(random_get_zero_to_one() * ENEMY_SPAWN_AT_A_TIME + 1) - 1)
                spawn_new_enemy();
        }
    }

    // update bullets
    for *bullet: bullets {
        bullet.life_timer -= dt;
        if bullet.life_timer <= 0 {
            remove bullet;
            continue;
        }

        bullet.pos += bullet.vel * dt;

        if bullet.friendly {
            for *enemy: enemies {
                if enemy.state != Enemy_State.SPAWNING && overlaps(bullet, enemy) {
                    remove enemy;
                    play_sound(game.hit_wall_sound, true);
                    game.screen_shake_percent = 0.85;
                    remove bullet;
                }
            }
        } else {
            if overlaps(bullet, *player) {
                damage_player();
                remove bullet;
            }
        }
    }

}

update_menu :: (dt: float) {
    using game;

    if up_pressed {
        if menu_selection > 0 {
            menu_selection -= 1;
        }
    }

    if down_pressed {
        if menu_selection < MAX_MENU_SELECTION {
            menu_selection += 1;
        }
    }

    if enter_pressed {
        if menu_selection == MENU_SELECTION_CONTINUE_GAME {
            mode = mode.GAME;
        } else if menu_selection == MENU_SELECTION_RESET_GAME {
            reset_game();
        } else if menu_selection == MENU_SELECTION_QUIT {
            game.quit = true;
        }
    }
}

update :: (dt: float) {
    if game.mode == game.mode.GAME then update_game(dt);
    if game.mode == game.mode.MENU then update_menu(dt);

    // Update the screen shake regardless of game mode, otherwise
    // we'll get infinte shaking while the game is paused.
    using game;
    if screen_shake_percent < 1.0 {
        screen_shake_percent += (screen_shake_step * dt);
        if screen_shake_percent > 1.0 screen_shake_percent = 1.0;
    }
}

// x, y directions, not coordinates
move_snake :: (x: int, y: int) -> has_not_died: bool, has_hit_wall: bool {
    game.can_move = true;

    assert((y == 0 && x != 0) || (x == 0 && y != 0));
    if x == 0 assert(y == -1 || y == 1);
    if y == 0 assert(x == -1 || x == 1);
    
    // the theory here is that we remove the tail, set the head as a body piece, then place the head at the new pos
    head := game.snake[0];
    target := head;
    target.x += x;
    target.y += y;
    
    if target.x < 0 || target.x >= game.grid_size return false, true;
    if target.y < 0 || target.y >= game.grid_size return false, true;

    {
        next := game.snake[1];
        assert(target.x != next.x || target.y != next.y);
    }

    oc := game.grid[target.x + target.y * game.grid_size];
    assert(oc != Occupant.HEAD);
    grow := false;
    shrink := false;
    new_apple := false;
    if #complete oc == {
        case Occupant.APPLE_1; grow = true; new_apple = true;
        case Occupant.APPLE_2; shrink = true; new_apple = true;
        
        // @TODO
        case Occupant.APPLE_3; new_apple = true; assert(false, "Apple 3 unimplemented!");
        
        case Occupant.BODY; return false, false;
        case Occupant.ROCK; return false, true;
        case Occupant.EMPTY; // do nothing
        case Occupant.HEAD ; assert(false);
    }
    
    game.grid[head.x + head.y * game.grid_size] = Occupant.BODY;
    
    tail := game.snake[game.snake.count-1];
    if !grow {
        game.grid[tail.x + tail.y * game.grid_size] = Occupant.EMPTY;
    } else {
        assert(shrink == false);
        array_add(*game.snake, tail); // it doesn't matter what we add here since it'll be overwritten by the loop below
    }
    
    if shrink {
        assert(grow == false);
        if game.snake.count > SMALLEST_SNAKE_SIZE {
            game.snake.count -= 1;
            
            tail := game.snake[game.snake.count-1];
            game.grid[tail.x + tail.y * game.grid_size] = Occupant.EMPTY;
        }
    }
    
    game.grid[target.x + target.y *game.grid_size] = Occupant.HEAD;
    
    // now we adjust positions in the snake array
    for < game.snake.count-2..0 {
        game.snake[it+1] = game.snake[it];
    }
    
    game.snake[0] = target;
    
    return true, false; // is valid move
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
    enemy.pos.x = random_get_within_range(0, INITIAL_GRID_SIZE - 1);
    enemy.pos.y = random_get_within_range(0, INITIAL_GRID_SIZE - 1);

    enemy.state = Enemy_State.SPAWNING;
    enemy.timer = random_get_within_range(1.0, 2.0);

    array_add(*game.enemies, enemy);
}

reset_game :: () {
    {
        using game.player;
        pos = make_vector2(0, 0);
    }

    // setup enemies
    {
        array_reset(*game.enemies);
        for 0..4 {
            spawn_new_enemy();
        }
    }
    

    game.grid_size = INITIAL_GRID_SIZE;
    array_reset(*game.grid);
    array_resize(*game.grid, game.grid_size * game.grid_size);
    array_reset(*game.snake);
    
    STARTING_X :: 3;
    STARTING_Y :: 2;
    
    game.snake_dir_x = 0;
    game.snake_dir_y = -1;

    p: type_of(game.snake[0]);
    for py: 0..INITIAL_SNAKE_SIZE-1 {
        pos := STARTING_X + (py + STARTING_Y) * game.grid_size;
        oc := Occupant.BODY;
        if py == 0 {
            oc = Occupant.HEAD;
        }
        game.grid[pos] = oc;
        p.x = STARTING_X;
        p.y = py + STARTING_Y;
        array_add(*game.snake, p);
    }
    
    game.mode = game.mode.GAME;

    game.down_pressed = false;
    game.up_pressed = false;
    game.left_pressed = false;
    game.right_pressed = false;
    game.enter_pressed = false;

    game.menu_selection = MENU_SELECTION_CONTINUE_GAME;

    game.player_has_crashed = false;
    game.snake_move_percent = 0;
    game.screen_shake_percent = 1;
    game.snake_failed_on_turn = false;
    game.snake_head_x_scale = 1;
}

logger :: (message: string, ident: string, mode: Log_Mode, data: *void) {
    print("[%] %", ident, message);
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
    context.logger = logger;

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

        for args {
            if it == "no_msaa" game.msaa = false;
            if it == "low" {
                // @TODO other graphics settings
                game.shadow_map_size = LOW_SHADOW_MAP_SIZE;
            }
            if it == "medium" {
                game.shadow_map_size = MEDIUM_SHADOW_MAP_SIZE;
            }
            if it == "high" {
                game.shadow_map_size = HIGH_SHADOW_MAP_SIZE;
            }
        }
    }
}

load_resources :: () {
    game.arrow_sound = load_audio_file("data/arrow.ogg");
    game.eat_sound = load_audio_file("data/eat_01.ogg");
    game.hit_wall_sound = load_audio_file("data/Jump_1.ogg");
    game.hurt_sound = load_audio_file("data/hurt.ogg");

    game.ambience = load_audio_file("data/Forest_Ambience.ogg");

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
    game.font, bytes_loaded = load_font("data", "KarminaBoldItalic.otf", FONT_HEIGHT);

    game.snake_head = load_obj("data/head.obj")[0];
    //game.snake_head = load_obj("data/decimated.obj")[0];
    game.snake_head_mid = load_obj("data/head_mid.obj")[0];
    game.snake_body_straight = load_obj("data/body.obj")[0];
    game.snake_body_angle = load_obj("data/body_corner.obj")[0];
    game.snake_tail = load_obj("data/tail.obj")[0];
    fruit_objs := load_obj("data/apple.obj");
    game.fruit = get_model_by_tag(fruit_objs, "Fruit_Body");
    game.fruit_leaf = get_model_by_tag(fruit_objs, "Leaf");

    game.bird_models[0] = load_obj("data/bird_000001.obj")[0];
    game.bird_models[1] = load_obj("data/bird_000002.obj")[0];
    game.bird_models[2] = load_obj("data/bird_000003.obj")[0];
    wall_model := load_obj("data/wall.obj")[0];
    game.wall = generate_wall_model_from_tile(wall_model);

    game.tree = load_obj("data/tree.obj");

    floor_tile := load_obj("data/generic_floor_tile.obj")[0];
    game.generic_floor_tile = generate_floor_model_from_tile(floor_tile, cast(s32) game.grid_size);

    buffer_model(game.snake_head);
    buffer_model(game.snake_head_mid);
    buffer_model(game.snake_body_straight);
    buffer_model(game.snake_body_angle);
    buffer_model(game.snake_tail);
    buffer_model(game.fruit);
    buffer_model(game.fruit_leaf);

    buffer_model(game.bird_models[0]);
    buffer_model(game.bird_models[1]);
    buffer_model(game.bird_models[2]);
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
    game.view = make_rotation_matrix4(q) * make_translation_matrix4(-game.camera_position);
    game.grid_offset_x = -(cast(float) game.grid_size / 2);
    game.grid_offset_y = -(cast(float) game.grid_size / 2);

    for events_this_frame {
        #if DEBUG_UI ImGui_Impl_ProcessEvent(it);

        if it.type == {
            case Event_Type.QUIT;
                game.quit = true;
            case Event_Type.KEYBOARD;
                key_down := it.key_pressed != 0;
                if it.key_code == {
                    case Key_Code.F8;
                        do_screenshot();

                    case cast(Key_Code)(#char "R"); if key_down reset_game();

                    case cast(Key_Code)(#char "W"); game.input_direction[Direction.UP]    = key_down;
                    case cast(Key_Code)(#char "A"); game.input_direction[Direction.LEFT]  = key_down;
                    case cast(Key_Code)(#char "S"); game.input_direction[Direction.DOWN]  = key_down;
                    case cast(Key_Code)(#char "D"); game.input_direction[Direction.RIGHT] = key_down;

                    case cast(Key_Code)(#char "I"); game.firing_in_direction[Direction.UP]    = key_down;
                    case cast(Key_Code)(#char "J"); game.firing_in_direction[Direction.LEFT]  = key_down;
                    case cast(Key_Code)(#char "K"); game.firing_in_direction[Direction.DOWN]  = key_down;
                    case cast(Key_Code)(#char "L"); game.firing_in_direction[Direction.RIGHT] = key_down;

                    case Key_Code.ARROW_UP;
                        game.up_pressed = key_down;
                        game.firing_in_direction[Direction.UP] = key_down;
                    case Key_Code.ARROW_DOWN;
                        game.down_pressed = key_down;
                        game.firing_in_direction[Direction.DOWN] = key_down;
                    case Key_Code.ARROW_LEFT;
                        game.left_pressed = key_down;
                        game.firing_in_direction[Direction.LEFT] = key_down;
                    case Key_Code.ARROW_RIGHT;
                        game.right_pressed = key_down;
                        game.firing_in_direction[Direction.RIGHT] = key_down;
                    case Key_Code.ENTER;
                        if key_down {
                            if it.alt_pressed then {
                                toggle_fullscreen(window, !game.fullscreen, *game.saved_window_info);
                                game.fullscreen = !game.fullscreen;
                            } else {
                                game.enter_pressed = true;
                            }
                        }
                    case cast(Key_Code)(#char "Q");
                        if key_down && it.shift_pressed game.quit = true;
                    case Key_Code.ESCAPE;
                        if it.key_pressed == 1 {
                            // XXX
                            game.quit = true;

                            if game.mode == game.mode.GAME then game.mode = game.mode.MENU;
                            else if game.mode == game.mode.MENU then game.mode = game.mode.GAME;
                        }
                }
        }
    }

    if gamepad.connected {
        if gamepad.buttons[Gamepad_Code.START] & Key_Current_State.START {
            if game.mode == game.mode.GAME then game.mode = game.mode.MENU;
            else if game.mode == game.mode.MENU then game.mode = game.mode.GAME;
        }

        if gamepad.buttons[Gamepad_Code.DPAD_UP] & Key_Current_State.START {
            game.up_pressed = true;
        }

        if gamepad.buttons[Gamepad_Code.DPAD_DOWN] & Key_Current_State.START {
            game.down_pressed = true;
        }

        if gamepad.buttons[Gamepad_Code.DPAD_LEFT] & Key_Current_State.START {
            game.left_pressed = true;
        }

        if gamepad.buttons[Gamepad_Code.DPAD_RIGHT] & Key_Current_State.START {
            game.right_pressed = true;
        }

        if gamepad.buttons[Gamepad_Code.A] & Key_Current_State.START {
            game.enter_pressed = true;
        }

        if gamepad.buttons[Gamepad_Code.B] & Key_Current_State.START {
            if game.mode == game.mode.MENU then game.mode = game.mode.GAME;
        }
    }

    #if DEBUG_UI new_imgui_frame(window);

    dt: float;
    now := get_time();
    if game.last_time dt = cast(float) (now - game.last_time);
    game.last_time = now;
    
    game.elapsed_time += dt;
    game.fps_time += dt;
    game.gamepad_time += dt;
    
    TICK_PERIOD : float64 : 1.0/60.0; // time between game updates
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

#if DEBUG_UI {
show_inspector: bool;
new_imgui_frame :: (window: *void) {
    ImGui_Impl_NewFrame(window, game.window_width, game.window_height);
    inspect("game", *game);
}
}

// @Note see macosx.jai for the MacOSX entry point that uses Cocoa/AppKit's run loop.
main :: () {
    init_game();

    direction_vectors[Direction.UP]    = make_vector2(0, -1);
    direction_vectors[Direction.DOWN]  = make_vector2(0, 1);
    direction_vectors[Direction.LEFT]  = make_vector2(-1, 0);
    direction_vectors[Direction.RIGHT] = make_vector2(1, 0);

    window := create_window(1600, 900, GAME_NAME);
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
        // setup ui
        ImGui_Impl_Init(window);
        ImGui.StyleColorsLight();
    }

    game.window_width = 1280;
    game.window_height = 720;

    game.sound_player = New(Sound_Player);
    game.sound_player.update_history = true;

    success := init(game.sound_player, window, true, true);
    // assert(success);

    load_resources();

    stream := play_sound(game.ambience, false);
    stream.flags |= stream.REPEATING;
    stream.user_volume_scale = 0.8;
    
    game.view = matrix4_identity();
    
    reset_game();

    vao: u32;
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);

    glGenBuffers(1, *game.immediate_draw_buffer_id);

    game.game_framebuffer = make_framebuffer(1280, 720, msaa=game.msaa);
    fb_width, fb_height := get_framebuffer_dimensions(null);
    resize_buffer(*game.game_framebuffer, fb_width, fb_height);

    light := new_Light();
    light.radiance *= make_vector3(4, 4, 4);
    array_add(*game.lights, light);

    game.camera_position = make_vector3(0, 8.0, 1.0);

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
        
        did_render_frame := do_frame(window);
        if did_render_frame then swap_buffers(window);
    }

    fini_game();
}
