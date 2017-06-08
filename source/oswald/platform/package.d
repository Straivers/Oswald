module oswald.platform;

enum platformPageScroll = uint.max;

//dfmt off
static immutable platformFunctions = [
    "CreateWindow",
    "DestroyWindow",

    "ShowWindow",
    "HideWindow",

    "SetTitle",

    "ProcessEvents"
];

static immutable platformConstants = [
    "ScrollLines"
];

static immutable platformTypes = [
    "WindowData",
];
//dfmt on

version (Windows)
{
    public import oswald.platform.win32;

    enum functionPrefix = "win32";
    enum typePrefix = "Win32";

    alias PlatformWindowData = Win32WindowData;
}

mixin(genPlatformAlias!"platform"(platformFunctions, functionPrefix));
mixin(genPlatformAlias!"platform"(platformConstants, functionPrefix));
// mixin(genPlatformTypeAliases(platformTypes, typePrefix));

private:

string genPlatformAlias(string aliasPrefix)(in string[] names, in string prefix)
{
    string result;

    foreach(name; names)
        result ~= "alias " ~ aliasPrefix ~ name ~ " = " ~ prefix ~ name ~ ";";

    return result;
}
