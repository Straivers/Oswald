module oswald.window;

import oswald.errors : WindowError;

enum maxTitleLength = 1024;

alias WindowResizeCallback = void function(OsWindow*, short, short);

struct WindowConfig
{
    string title;

    ushort width;
    ushort height;
    bool hidden;
    bool resizeable;
}

struct OsWindow
{
    @safe @nogc nothrow:

    import oswald.platform;
    import oswald.input : WindowInput;

    static WindowError createNew(WindowConfig config, OsWindow* destination)
    {
        auto error = platformCreateWindow(config, destination._platformData, destination);
        destination.input = WindowInput(destination);
        return error;
    }

    ~this()
    {
        platformDestroyWindow(_platformData);
    }

    /**
     * `true` if a request to close the window was made, `false`
     * otherwise.
     */
    @property bool isCloseRequested() const
    {
        return _isCloseRequested;
    }

    @property PlatformWindowData platformData()
    {
        return _platformData;
    }

    @property ref WindowInput input()
    {
        return _input;
    }

    @property void title(string newTitle)
    {
        platformSetTitle(_platformData, newTitle);
    }

    version (Windows) alias win32 = platformData;

    void show()
    {
        platformShowWindow(_platformData);
    }

    void hide()
    {
        platformHideWindow(_platformData);
    }

    WindowResizeCallback resizeCallback;

package(oswald):

    @property void isCloseRequested(bool icr)
    {
        _isCloseRequested = icr;
    }

    ushort _width;
    ushort _height;

private:
    PlatformWindowData _platformData;
    WindowInput _input;

    bool _isCloseRequested;
}
