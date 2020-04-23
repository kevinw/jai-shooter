
CPP_STYLE_COMMENTS :: false;

// for .obj wavefront files
HASH_CHARACTER_STARTS_COMMENT :: true;

Token :: struct {
    
    Type :: enum u32 {
        UNINITIALIZED;
        IDENTIFIER :: 256;
        INTEGER;
        FLOAT;
        SQSTRING;
        DQSTRING;
        
        EOF;
    }
    
    type: Type;
    
    integer_value: s64;
    float_value: float64;
    string_value: string;
    
    using location: Source_Code_Location;
    offset_into_buffer: s64;
}

// @Cleanup custom type printing for the standard print?
to_string :: (tok: Token) -> string {
    if #complete tok.type == {
        case Token.Type.UNINITIALIZED;
        return copy_string("(uninitialized token)");
        case Token.Type.IDENTIFIER;
        return copy_string(tok.string_value);
        case Token.Type.INTEGER;
        return sprint("%", tok.integer_value);
        case Token.Type.FLOAT;
        return sprint("%", tok.float_value);
        case Token.Type.SQSTRING;
        return sprint("'%'", tok.string_value);
        case Token.Type.DQSTRING;
        return sprint("\"%\"", tok.string_value);
        case Token.Type.EOF;
        return copy_string("(end-of-file)");
        case;
        // @Hack
        c: u8 = xx tok.type;
        s: string;
        s.data = *c;
        s.count = 1;
        return sprint("char(%)", s);
    }
}

Lexer :: struct {
    data: string;
    
    line_number: s64 = 1;
    character_number: s64 = 1;
    offset_into_buffer: s64;
    filename: string;

    error_callback := default_error_callback;
}

default_error_callback :: (loc: Source_Code_Location, fmt: string, args: .. Any) {
    message := tprint(fmt, ..args);
    logprint("lexer", "%:%,%: %", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

get_tokens :: (filename: string, input: string) -> [] Token {
    tokens: [..] Token;
    
    lex: Lexer;
    lex.data = input;
    lex.filename = filename;
    
    success := true;
    while success {
        tok: Token;
        success, tok = get_token(*lex);
        array_add(*tokens, tok);
    }

    return tokens;
}

make_token :: (lex: *Lexer, type: Token.Type) -> Token {
    t: Token;
    t.type = type;
    t.location = get_location(lex);
    t.offset_into_buffer = lex.offset_into_buffer;
    return t;
}

decimal_string_contains_dot :: (data: string) -> bool {
    str := data;

    while str.count && (is_number(str[0]) || str[0] == #char "_" || str[0] == #char ".") {
        if str[0] == #char "." return true;
        advance(*str);
    }

    return false;
}

is_whitespace :: (c: u32) -> bool {
    // We got rid of the \v escape code so I took it out of here. It is unlikely you would
    // have this in your map data!   -jblow, 3 June 2018.
    return c == #char " " || c == #char "\t" || /*c == #char "\v" ||*/ c == #char "\r" || c == #char "\n";
}

starts_identifier :: (c: u32) -> bool {
    return c == #char "_" || (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

is_number :: (c: u32) -> bool {
    return (c >= #char "0" && c <= #char "9");
}

is_hex_number :: (c: u32) -> bool {
    return (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F") || is_number(c);
}

continues_identifier :: (c: u32) -> bool {
    return starts_identifier(c) || is_number(c);
}

at_end :: (lex: *Lexer) -> bool {
    return lex.data.count <= 0;
}

eat_char :: (lex: *Lexer, count := 1) {
    advance(*lex.data, count);
    lex.character_number += count;
    lex.offset_into_buffer += count;
}

get_location :: (lex: *Lexer) -> Source_Code_Location {
    s: Source_Code_Location;
    s.fully_pathed_filename = lex.filename;
    s.line_number = lex.line_number;
    s.character_number = lex.character_number;
    return s;
}

// TEST_STRING :: #string DONE
// 12_3456_7890
// DONE

// #run {
//     context.logger = logger;
//     tokens := get_tokens(#file, TEST_STRING);
//     return;
// };

get_token :: (lex: *Lexer) -> success: bool, tok: Token {
    
    while true {
        starting := lex.data.count;
        while !at_end(lex) && is_whitespace(lex.data[0]) {
            c := lex.data[0];
            if c == #char "\n" {
                lex.line_number += 1;
                lex.character_number = 0;
            }
            
            eat_char(lex);
        }
        
        if at_end(lex) return false, make_token(lex, Token.Type.EOF);
        
        // handle comments
        if CPP_STYLE_COMMENTS && lex.data[0] == #char "/" && lex.data.count > 1 {
            if lex.data[1] == #char "/" {
                eat_char(lex, 2);
                
                while !at_end(lex) && lex.data[0] != #char "\n" {
                    eat_char(lex);
                }
            } else if lex.data[1] == #char "*" {
                eat_char(lex, 2);
                
                while !at_end(lex) {
                    if lex.data[0] == #char "\n"{
                        lex.line_number += 1;
                        lex.character_number = 0;
                    } else if lex.data[0] == #char "*" && lex.data.count > 1 {
                        if lex.data[1] == #char "/" {
                            eat_char(lex, 2);
                            break;
                        }
                    }
                    
                    eat_char(lex);
                }
            }
        } else if HASH_CHARACTER_STARTS_COMMENT {
            if lex.data[0] == #char "#" {
                eat_char(lex);
                
                
                while !at_end(lex) && lex.data[0] != #char "\n" {
                    eat_char(lex);
                }
            }
        }
        
        // if we've made no progress on eliminating whitespace or comments then move on!
        if lex.data.count == starting
            break;
    }
    
    if starts_identifier(lex.data[0]) {
        tok := make_token(lex, Token.Type.IDENTIFIER);
        length: s64;
        ident := lex.data;
        while !at_end(lex) && continues_identifier(lex.data[0]) {
            length += 1;
            eat_char(lex, 1);
        }
        ident.count = length;

        tok.string_value = ident;
        return true, tok;
    }

    if is_number(lex.data[0]) {
        if lex.data[0] == #char "0" && !decimal_string_contains_dot(lex.data) {
            tok := make_token(lex, Token.Type.INTEGER);
            value: u64;
            eat_char(lex);

            if lex.data[0] == #char "x" || lex.data[0] == #char "X" {
                eat_char(lex);

                success := true;
                while !at_end(lex) && continues_identifier(lex.data[0]) {
                    if lex.data[0] == #char "_" {
                        eat_char(lex);
                        continue;
                    }

                    if !is_hex_number(lex.data[0]) {
                        lex.error_callback(get_location(lex), "invalid character \"%\" in hex constant.\n", slice(lex.data, 0, 1));
                        success = false;
                        break;
                    }

                    value = value << 4;
                    if is_number(lex.data[0]) value |= (lex.data[0] - #char "0");
                    else value |= ((to_lower(lex.data[0]) - #char "a") + 0xA);
                    eat_char(lex);
                }

                tok.integer_value = cast(s64) value;
                return success, tok;
            } else {
                // octal
                success := true;
                while !at_end(lex) && is_number(lex.data[0]) {
                    if lex.data[0] > #char "7" {
                        lex.error_callback(get_location(lex), "invalid digit \"%\" in octal constant.\n", slice(lex.data, 0, 1));
                        success = false;
                        break;
                    }

                    value = value << 3;
                    value |= (lex.data[0] - #char "0");
                    eat_char(lex);
                }

                tok.integer_value = cast(s64) value;
                return success, tok;
            }
        }

        // decimal int or float
        if decimal_string_contains_dot(lex.data) {
            tok := make_token(lex, Token.Type.FLOAT);
            has_hit_dot := false;
            modifier: float64 = 10.0;
            value: float64;

            success := true;
            while !at_end(lex) && (is_number(lex.data[0]) || lex.data[0] == #char "_" || lex.data[0] == #char ".") {
                if lex.data[0] == #char "_" {
                    eat_char(lex);
                    continue;
                }

                if lex.data[0] == #char "." {
                    if has_hit_dot {
                        lex.error_callback(get_location(lex), "More than one '.' found in float constant.\n");
                        success = false;
                        break;
                    }

                    eat_char(lex);
                    has_hit_dot = true;
                    continue;
                }

                if !has_hit_dot {
                    value = value * 10.0;
                    assert(is_number(lex.data[0]));
                    value += cast(float64) (lex.data[0] - #char "0");
                } else {
                    assert(is_number(lex.data[0]));
                    value += (cast(float64) (lex.data[0] - #char "0") / modifier);
                    modifier = modifier * 10.0;
                }

                eat_char(lex);
            }

            tok.float_value = value;
            return success, tok;
        } else {
            // decimal int
            tok := make_token(lex, Token.Type.INTEGER);
            value: u64;

            success := true;
            while !at_end(lex) && (is_number(lex.data[0]) || lex.data[0] == #char "_" ) {
                if lex.data[0] == #char "_" {
                    eat_char(lex);
                    continue;
                }

                value = value * 10;
                value += (lex.data[0] - #char "0");
                eat_char(lex);
            }

            tok.integer_value = cast(s64) value;
            return success, tok;
        }
    }
    
    
    // single character
    char := lex.data[0];
    tok := make_token(lex, cast(Token.Type) char);
    eat_char(lex, 1);
    return true, tok;
}
