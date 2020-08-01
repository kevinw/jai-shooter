
#import "Basic";
#import "Compiler";
#import "String";
#import "Process";
#import "File_Utilities";
#import "File";

#if OS == .WINDOWS {
    Windows_Resources :: #import "Windows_Resources";
    Ico_File :: #import "Ico_File";
}

#if OS == .MACOS {
    Bundler :: #import "MacOS_Bundler";
}

GAME_NAME :: "Shooter";

BUILD_COCOA_APP :: true;

build :: (building_executable := true, build_release := false) -> Workspace {
    set_working_directory(#filepath);
    
    opts := get_build_options();
    opts.output_type = Build_Output_Type.NO_OUTPUT;
    set_build_options(opts);

    // set_optimization_level(*opts, 3, 3);
    
    opts.output_type = Build_Output_Type.EXECUTABLE;
    opts.output_executable_name = GAME_NAME;
    opts.output_path = "run_tree/";
    w := compiler_create_workspace(sprint("% by Kevin Watters", GAME_NAME)); // I think this @Leaks ?
    if building_executable then compiler_begin_intercept(w);

    if BUILD_COCOA_APP && OS == .MACOS {
        opts.entry_point_name = "cocoa_application_main";
    }

    if build_release {
        set_optimization_level(*opts, 3, 0);
    }

    set_build_options(opts, w);
    add_build_file("src/main.jai", w);
    add_build_string(sprint("GAME_NAME :: \"%\";", GAME_NAME), w); // I think this @Leaks ?
    
    if building_executable {
        // Wait for COMPLETE message so we know our executable is built
        while true {
            using Compiler_Message.Kind;
            
            message := compiler_wait_for_message();
            if !message continue;
            if message.workspace != w continue;
            if message.kind == COMPLETE break;
        }

        compiler_end_intercept(w);

        #if OS == .WINDOWS {
            exe_name := sprint("%1%2.exe", opts.output_path, opts.output_executable_name);
            translate_path(exe_name, #char "\\");
            defer free(exe_name);

            print("setting icon to %\n", exe_name);

            ico_data := Ico_File.create_ico_file_from_bitmap_filename("run_tree\\apple.png");
            defer free(ico_data);
            if !ico_data then print("Could not load image for icon: run_tree/apple.png\n");
            else Windows_Resources.set_icon_by_data(exe_name, ico_data);

            manifest_options: Windows_Resources.Manifest_Options;
            manifest_options.dpi_aware = false;
            Windows_Resources.add_manifest_to_executable(exe_name, manifest_options);
        }

        #if OS == .MACOS {
            success, exit_code, output, error := os_run_command("ibtool", "src/Main.storyboard", "--compile", "run_tree/Main.storyboardc");
            if !success {
                print("Could not run ibtool on Main.storyboard.");
                exit(1);
            } else {
                if output || error then print("ibtool:\n%\n%\n", output, error);

                free(output);
                free(error);
            }

            app_bundle, resources_path := Bundler.create_app_bundle(GAME_NAME, tprint("%/%", opts.output_path, opts.output_executable_name), "run_tree/apple.png", "run_tree/data", false, write_plist=false);
            copy_file("run_tree/Info.plist", tprint("%/Contents/Info.plist", app_bundle));

            resource_output_path := tprint("%/%", resources_path, "Main.storyboardc");
            make_directory_if_it_does_not_exist(resource_output_path);
            copy_files_recursively("run_tree/Main.storyboardc", resource_output_path);
        }
    }
    return w;
}

make_directory_tree :: (_path: string) {
    path := _path;
    if path.count && path[path.count-1] == #char "/" {
        path.count -= 1;
    }

    if path == "" return;
    parent := path_strip_filename(path);
    make_directory_tree(parent);
    make_directory_if_it_does_not_exist(path);
}

copy_files_recursively :: (source: string, dest: string) {
    paths: [2] string;
    paths[0] = source;
    paths[1] = dest;

    visitor :: (info: *File_Visit_Info, paths: [2] string) {
        relative_path := info.full_name;
        advance(*relative_path, paths[0].count);
        out_path := concatenate(paths[1], "/", relative_path);
        make_directory_tree(path_strip_filename(out_path));
        copy_file(info.full_name, out_path);
    }

    res := visit_files(paths[0], true, paths, visitor);
    assert(res);
}

compile_and_run :: () {
    w := build(false);
    opts := get_build_options(w);
    opts.output_type = Build_Output_Type.NO_OUTPUT;
    set_build_options(opts, w);
    add_build_string("#run main();", w);
}

#run build();
// #run compile_and_run();
