#import "Basic";

func_with_multiple_returns :: (val: bool) -> (int, bool) {
    return 42, val;
}

main :: () {
    {
        junk: int;
        ok: bool;
        junk, ok = func_with_multiple_returns(true);
        print("ok should be true: %\n", ok);  // prints false--looks good!

        junk, ok = func_with_multiple_returns(false);
        print("ok should be false: %\n", ok); // prints false--looks good!
    }

    {
        other_junk, other_ok := func_with_multiple_returns(true);
        print("other_ok should be true: %\n", other_ok); // prints true--looks good!

        // HERE'S THE BUG:
        other_junk, other_ok := func_with_multiple_returns(false);

        // ^^^ There is no warning about shadowing `other_ok` here.

        // Also, it prints true, the value of the *first* `other_ok`!
        print("other_ok should be false: % <- UH OH \n", other_ok); 
    }

}