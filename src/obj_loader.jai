
#load "lexer.jai";

#scope_file

Obj_Parser :: struct {
    tokens: [] Token;
    current_token: s64;
    data: string;
}

eat_token :: next_token;
next_token :: (using p: *Obj_Parser) -> Token {
    if current_token >= tokens.count return tokens[tokens.count-1];
    tok := tokens[current_token];
    current_token += 1;
    return tok;
}

peek_token :: (using p: *Obj_Parser) -> Token {
    if current_token >= tokens.count return tokens[tokens.count-1];
    return tokens[current_token];
}

eat_possible_token :: (p: *Obj_Parser, type: Token.Type) -> did_eat: bool {
    tok := peek_token(p);
    if tok.type == type {
        eat_token(p);
        return true;
    }
    
    return false;
}

eat_possible_token :: (p: *Obj_Parser, type: Token.Type.loose) -> did_eat: bool {
    return eat_possible_token(p, cast(Token.Type) type);
}

eat_possible_directive :: (p: *Obj_Parser, name: string) -> did_eat: bool {
    tok := peek_token(p);
    
    if tok.type == Token.Type.IDENTIFIER {
        if name == tok.string_value {
            eat_token(p);
            return true;
        }
    }
    
    return false;
}

expect :: (p: *Obj_Parser, type: Token.Type, source_loc := #caller_location) {
    tok := peek_token(p);
    
    if tok.type != type {
        loc := tok.location;
        print("error:%:%,%: expected token % but got % at %.\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, type, tok.type, source_loc);
    }
}

expect_and_eat :: (p: *Obj_Parser, type: Token.Type, loc := #caller_location) {
    expect(p, type, loc);
    eat_token(p);
}

expect_and_eat :: (p: *Obj_Parser, type: Token.Type.loose, loc := #caller_location) {
    expect(p, xx type, loc);
    eat_token(p);
}

parse_float :: (p: *Obj_Parser) -> float {
    negate := eat_possible_token(p, #char "-");
    
    tok := peek_token(p);
    value: float;
    if tok.type == Token.Type.INTEGER {
        value = cast(float) tok.integer_value;
        expect_and_eat(p, Token.Type.INTEGER);
    } else {
        expect(p, Token.Type.FLOAT);
        tok := next_token(p);
        value = cast(float) tok.float_value;
    }
    if negate value = -value;
    return xx value;
}

parse_integer :: (p: *Obj_Parser) -> s64 {
    expect(p, Token.Type.INTEGER);
    tok := next_token(p);
    
    // @TODO maybe handle negative(-) here ?
    return tok.integer_value;
}

parse_vector3 :: (p: *Obj_Parser) -> Vector3 {
    return make_vector3(parse_float(p), parse_float(p), parse_float(p));
}

parse_vector2 :: (p: *Obj_Parser) -> Vector2 {
    return make_vector2(parse_float(p), parse_float(p));
}

parse_face_indices :: (p: *Obj_Parser) -> vertex: int, texture: int, normal: int {
    expect(p, Token.Type.INTEGER);
    tok := next_token(p);
    
    v := tok.integer_value;
    expect_and_eat(p, #char "/");
    
    t := 0;
    tok = peek_token(p);
    if tok.type == Token.Type.INTEGER {
        t = tok.integer_value;
        eat_token(p);
    }
    
    expect_and_eat(p, #char "/");
    
    expect(p, Token.Type.INTEGER);
    tok = next_token(p);
    
    assert(tok.type == Token.Type.INTEGER);
    n := tok.integer_value;
    return v, t, n;
}

Obj_Mtl :: struct {
    name: string;
    Ns: float64;
    Ka: Vector3;
    Kd: Vector3;
    Ks: Vector3;
    Ke: Vector3;
    Ni: float64;
    d: float64;
    illum: int;
    
    map_Kd: string; // full path
}

parse_mtl :: (p: *Obj_Parser) -> [] *Obj_Mtl {
    mtls: [..] *Obj_Mtl;
    current: *Obj_Mtl;
    
    while peek_token(p).type != Token.Type.EOF {
        if eat_possible_directive(p, "newmtl") {
            current = New(Obj_Mtl);
            array_add(*mtls, current);

            name := parse_path(p);
            current.name = copy_string(name);
        } else if eat_possible_directive(p, "Ns") {
            current.Ns = parse_float(p);
        } else if eat_possible_directive(p, "Ka") {
            current.Ka = parse_vector3(p);
        } else if eat_possible_directive(p, "Kd") {
            current.Kd = parse_vector3(p);
        } else if eat_possible_directive(p, "Ks") {
            current.Ks = parse_vector3(p);
        } else if eat_possible_directive(p, "Ke") {
            current.Ke = parse_vector3(p);
        } else if eat_possible_directive(p, "Ni") {
            current.Ni = parse_float(p);
        } else if eat_possible_directive(p, "d") {
            current.d = parse_float(p);
        } else if eat_possible_directive(p, "illum") {
            current.illum = parse_integer(p);
        } else if eat_possible_directive(p, "map_Kd") {
            path := parse_path(p);
            full := sprint("%1/%2", path_strip_filename(peek_token(p).fully_pathed_filename), path);
            // print("full: %\n", full);
            current.map_Kd = full;
        } else {
            e := peek_token(p);
            print("%:%,%: error:unexpected token: %\n", e.fully_pathed_filename, e.line_number, e.character_number, to_string(peek_token(p)));
        }
    }
    
    return mtls;
}

parse_path :: (p: *Obj_Parser) -> string {
    tok := peek_token(p);
    // @Hack this assumes the input here is valid following a mtllib!
    current_line := tok.line_number;
    offset_start := tok.offset_into_buffer;
    
    while tok.type != Token.Type.EOF && tok.line_number == current_line {
        eat_token(p);
        tok = peek_token(p);
    }
    
    start := p.data;
    advance(*start, offset_start);
    end: s64;
    while (start.count-end) > 0 && start[end] != #char "\n" {
        end += 1;
    }
    
    start.count = end;
    return start;
}

load_texture :: (path: string) -> *Texture {
    if path == "" return null;

    map := New(Texture);
    load_texture_from_file(map, path);
    
    glBindTexture(GL_TEXTURE_2D, map.platform_specific.gl_handle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
    return map;
}

parse_obj :: (p: *Obj_Parser) -> [] *Model {
    object: *Model;
    mesh: *Mesh;
    models: [..] *Model;

    mtls: [..] *Obj_Mtl;

    positions: [..] Vector3;
    normals: [..] Vector3;
    tex_coords: [..] Vector2;

    defer array_reset(*positions);
    defer array_reset(*normals);
    defer array_reset(*tex_coords);

    defer {
        for mtls {
            free(it.name);
            free(it);
        }
        array_reset(*mtls);
    };

    array_add(*tex_coords, make_vector2(0, 0));

    while peek_token(p).type != Token.Type.EOF {
        if eat_possible_directive(p, "mtllib") {
            the_path := parse_path(p);
            filepath := concatenate(path_strip_filename(peek_token(p).fully_pathed_filename), the_path);
            defer free(filepath);
            data := read_entire_file(filepath);
            defer free(data);
            if !data {
                print("error: could not open file: '%'.\n", filepath);
                dummy: [] *Model;
                return dummy;
            }
            
            parser: Obj_Parser;
            parser.data = data;
            parser.tokens = get_tokens(filepath, data);
            defer array_reset(*parser.tokens);

            new_mtls := parse_mtl(*parser);
            array_add(*mtls, ..new_mtls);
            array_reset(*new_mtls);
        } else if eat_possible_directive(p, "o") {
            ident := parse_path(p); // eat the identifier, it may be separated by '.' or other non-ident character tokens
            // print("ident: %\n", ident);
            object = New(Model);
            object.tag = copy_string(ident);
            mesh = New(Mesh);
            array_add(*object.meshes, mesh);
            array_add(*models, object);
        } else if eat_possible_directive(p, "v") {
            array_add(*positions, parse_vector3(p));

            // @TODO optional w component
        } else if eat_possible_directive(p, "vn") {
            array_add(*normals, parse_vector3(p));
        } else if eat_possible_directive(p, "vt") {
            array_add(*tex_coords, parse_vector2(p));
        } else if eat_possible_directive(p, "usemtl") {
            expect(p, Token.Type.IDENTIFIER);
            lookup_name := parse_path(p);

            target: *Obj_Mtl;
            for mtls
                if it.name == lookup_name {
                    target = it;
                    break;
                }

            assert(target != null);

            mat := New(Material);
            // mat.ambient = target.Ka;
            mat.diffuse = target.Kd;
            // mat.specular = target.Ks;
            mat.diffuse_texture = load_texture(target.map_Kd);
            mesh.material = mat;
        } else if eat_possible_directive(p, "s") {
            eat_token(p); // @TODO ignore smooth shading directive for now. Should we always smooth shade or always flat shade?
        } else if eat_possible_directive(p, "f") {
            v0, t0, n0 := parse_face_indices(p);
            v1, t1, n1 := parse_face_indices(p);
            v2, t2, n2 := parse_face_indices(p);

            tv0: Vector2;
            tv1: Vector2;
            tv2: Vector2;

            if t0 > 0 tv0 = tex_coords[t0-1];
            if t1 > 0 tv1 = tex_coords[t1-1];
            if t2 > 0 tv2 = tex_coords[t2-1];

            // flip the texture coords
            tv0.y = 1.0 - tv0.y;
            tv1.y = 1.0 - tv1.y;
            tv2.y = 1.0 - tv2.y;

            va0 := make_vertex(positions[v0-1], normals[n0-1], tv0);
            va1 := make_vertex(positions[v1-1], normals[n1-1], tv1);
            va2 := make_vertex(positions[v2-1], normals[n2-1], tv2);
            array_add(*mesh.vertices, va0);
            array_add(*mesh.vertices, va1);
            array_add(*mesh.vertices, va2);
        } else {
            e := peek_token(p);
            print("%:%,%: error:unexpected token: %\n", e.fully_pathed_filename, e.line_number, e.character_number, to_string(peek_token(p)));
            break;
        }
    }
    
    return models;
}

#scope_export

load_obj :: (filename: string) -> [] *Model {
    data := read_entire_file(filename);
    defer free(data);

    dummy: [] *Model;
    if !data return dummy;
    
    parser: Obj_Parser;
    parser.data = data;
    parser.tokens = get_tokens(filename, data);
    defer array_reset(*parser.tokens);

    return parse_obj(*parser);
}
