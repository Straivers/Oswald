module oswald.platform.win32;

import oswald.event;
import oswald.input;
import oswald.window;
import core.sys.windows.windows;

pragma(lib, "user32");

__gshared bool registered_window_class;
__gshared uint num_scroll_lines;

immutable wndclass_name = "blip_window_class\0"w;
immutable window_property = "blip_property\0"w;

HCURSOR get_cursor(CursorIcon icon) nothrow {
    static HCURSOR[16] cursor_icons;

    if (cursor_icons[icon] is null && icon < CursorIcon.UserDefined1) {
        auto ico = () {
            switch (icon) with (CursorIcon) {
                case Pointer: return IDC_ARROW;
                case Wait: return IDC_WAIT;
                case IBeam: return IDC_IBEAM;
                case ResizeHorizontal: return IDC_SIZEWE;
                case ResizeVertical: return IDC_SIZENS;
                case ResizeNorthwestSoutheast: return IDC_SIZENWSE;
                case ResizeCornerNortheastSouthwest: return IDC_SIZENESW;
                default: assert(false);
            }
        } ();

        cursor_icons[icon] = LoadCursor(null, ico);
    }

    return cursor_icons[icon];
}

HWND win32_create_window(WindowConfig config, void* window_data) nothrow {
    if (!registered_window_class) { // the first time a window is created
        WNDCLASSEXW wc;
        wc.cbSize = WNDCLASSEXW.sizeof;
        wc.style = CS_OWNDC | CS_VREDRAW | CS_HREDRAW;
        wc.lpfnWndProc = &window_procedure;
        wc.hInstance = GetModuleHandle(null);
        // wc.hCursor = get_cursor(CursorIcon.Pointer);
        wc.lpszClassName = &wndclass_name[0];

        auto err = RegisterClassExW(&wc);
        assert(err != 0, "Failed to register window class");

        registered_window_class = true;

        SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &num_scroll_lines, 0);
    }

    wchar[256] title_buffer;
    auto win32_title = write_wchar_buffer(config.title, title_buffer);

    auto style = WS_OVERLAPPEDWINDOW;
    
    if (!config.resizable)
        style ^= WS_SIZEBOX;

    //dfmt off
    HWND hwnd = CreateWindowExW(
        0,                              //Extended style flags
        &wndclass_name[0],              //The name of the window class
        win32_title.ptr,                //The name of the window
        style,                          //Window Style
        CW_USEDEFAULT, CW_USEDEFAULT,   //(x, y) positions of the window
        config.width, config.height,    //The width and height of the window
        NULL,                           //Parent window
        NULL,                           //Menu
        GetModuleHandleW(NULL),         //hInstance handle
        NULL
    );
    //dfmt on

    assert(hwnd, "Failed to create window!");

    win32_bind_handle(hwnd, window_data);
    win32_set_window_mode(hwnd, WindowMode.Windowed);
    win32_set_window_cursor(hwnd, CursorIcon.Pointer);

    return hwnd;
}

void win32_destroy_window(HWND window) nothrow {
    DestroyWindow(window);
}

void win32_close_window(HWND window) nothrow {
    PostMessageW(window, WM_CLOSE, 0, 0);
}

void win32_bind_handle(HWND window, void* window_data) nothrow {
    SetPropW(window, window_property.ptr, window_data);
}

void win32_set_window_mode(HWND window, WindowMode mode) nothrow {
    switch (mode) {
        case WindowMode.Hidden:
            ShowWindow(window, SW_HIDE);
            break;
        case WindowMode.Windowed:
            ShowWindow(window, SW_SHOWNORMAL);
            break;
        case WindowMode.Minimized:
            ShowWindow(window, SW_SHOWMINIMIZED);
            break;
        case WindowMode.Maximized:
            ShowWindow(window, SW_SHOWMAXIMIZED);
            break;
        default:
    }
}

void win32_resize_window(HWND window, ushort width, ushort height) nothrow {
    RECT rect;
    GetWindowRect(window, &rect);

    MoveWindow(window, rect.left, rect.top, width, height, true);
}

void win32_retitle_window(HWND window, const char[] new_title) nothrow {
    wchar[256] title_buffer;
    auto win32_title = write_wchar_buffer(new_title, title_buffer);

    SetWindowText(window, win32_title.ptr);
}

void win32_set_window_cursor(HWND window, CursorIcon icon) nothrow {
    SetCursor(get_cursor(icon));
}

void win32_poll_events() nothrow {
    win32_poll_events(null);
}

void win32_poll_events(HWND window) nothrow {
    MSG msg;

    while (PeekMessage(&msg, window, 0, 0, PM_REMOVE) != 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
}

void win32_wait_events() nothrow {
    win32_wait_events(null);
}

void win32_wait_events(HWND window) nothrow {
    MSG msg;

    const quit = GetMessage(&msg, window, 0, 0);
    
    TranslateMessage(&msg);
    DispatchMessage(&msg);

    if (quit == 0)
        return;

    while (PeekMessage(&msg, window, 0, 0, PM_REMOVE) != 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
}

wchar[] write_wchar_buffer(const char[] from, wchar[] destination_buffer) nothrow
        in (from.length < destination_buffer.length) {
    import std.utf: byWchar;
    import std.range: enumerate;

    foreach (i, c; from.byWchar.enumerate)
        destination_buffer[i] = c;

    destination_buffer[from.length] = 0;
    return destination_buffer[0 .. from.length];
}

void dispatch(string name, Args...)(OsWindow* window, Args args) nothrow {
    import std.format: format;

    try {
        if (window is null || window.event_handler is null)
            mixin("global_event_handler.%s(window, args);".format(name));
        else {
            mixin(
                "if (window.event_handler.%s) window.event_handler.%s(window, args); else global_event_handler.%s(window, args);".format(
                    name, 
                    name,
                    name
                )
            );
        }
    } catch (Exception e) {}
}

extern (Windows) LRESULT window_procedure(HWND hwnd, uint msg, WPARAM wp, LPARAM lp) nothrow {
    auto window = cast(OsWindow*) GetPropW(hwnd, window_property.ptr);

    if (window is null)
        return DefWindowProc(hwnd, msg, wp, lp);

    switch (msg) {
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYUP:
        const is_extended = (lp & 0x01000000) != 0;
        const scancode = (lp & 0x00FF0000) >> 16;
        const state = lp >> 31 ? ButtonState.Released : ButtonState.Pressed;

        const extended_aware = (window.event_handler && window.event_handler.is_left_right_key_aware) ||
                                global_event_handler.is_left_right_key_aware;

        auto key = () {
            auto k = keycode_table[wp];

            if (!extended_aware)
                return k;

            switch (k) with (KeyCode) {
                case Control:
                    return is_extended ? RightControl : LeftControl;
                case Shift:
                    return keycode_table[MapVirtualKey(scancode, MAPVK_VSC_TO_VK_EX)];
                case Super:
                    return is_extended ? RightSuper : LeftSuper;
                case Alt:
                    return is_extended ? RightAlt : LeftAlt;
                default:
                    return k;
            }
        } ();

        window.dispatch!"on_key"(key, state);
        return 0;

    case WM_LBUTTONDOWN:
        window.dispatch!"on_mouse_button"(MouseButton.Left, ButtonState.Pressed);
        return 0;

    case WM_LBUTTONUP:
        window.dispatch!"on_mouse_button"(MouseButton.Left, ButtonState.Released);
        return 0;

    case WM_MBUTTONDOWN:
        window.dispatch!"on_mouse_button"(MouseButton.Middle, ButtonState.Pressed);
        return 0;

    case WM_MBUTTONUP:
        window.dispatch!"on_mouse_button"(MouseButton.Middle, ButtonState.Released);
        return 0;

    case WM_RBUTTONDOWN:
        window.dispatch!"on_mouse_button"(MouseButton.Right, ButtonState.Pressed);
        return 0;

    case WM_RBUTTONUP:
        window.dispatch!"on_mouse_button"(MouseButton.Right, ButtonState.Released);
        return 0;

    case WM_XBUTTONDOWN:
        const id = [MouseButton.Button_4, MouseButton.Button_5][HIWORD(wp)];
        window.dispatch!"on_mouse_button"(id, ButtonState.Pressed);
        return 0;

    case WM_XBUTTONUP:
        const id = [MouseButton.Button_4, MouseButton.Button_5][HIWORD(wp)];
        window.dispatch!"on_mouse_button"(id, ButtonState.Released);
        return 0;

    case WM_MOUSELEAVE:
        window.has_cursor = false;
        window.dispatch!"on_cursor_exit"();
        return 0;

    case WM_MOUSEMOVE:
        union Splitter {
            LPARAM lparam;
            struct{ short x, y; }
        }

        auto splitter = Splitter(lp);

        if (window.has_cursor)
            window.dispatch!"on_cursor_move"(splitter.x, splitter.y);
        else {
            TRACKMOUSEEVENT tme;
            tme.cbSize = tme.sizeof;
            tme.dwFlags = TME_LEAVE | TME_HOVER;
            tme.hwndTrack = hwnd;
            tme.dwHoverTime = HOVER_DEFAULT;
            TrackMouseEvent(&tme);

            window.has_cursor = true;
            window.dispatch!"on_cursor_enter"(splitter.x, splitter.y);
            SetCursor(get_cursor(window.cursor_icon));
        }

        return 0;

    case WM_MOUSEWHEEL:
        auto lines = GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA;
        lines *= num_scroll_lines;
        window.dispatch!"on_scroll"(lines);
        return 0;

    case WM_SIZE:
        window.dispatch!"on_window_resize"(LOWORD(lp), HIWORD(lp));
        return 0;

    case WM_CLOSE:
        window.close_requested = true;
        window.dispatch!"on_close_request"();
        return 0;

    case WM_DESTROY:
        window.dispatch!"on_window_close"();
        return 0;

    default:
        return DefWindowProc(hwnd, msg, wp, lp);
    }
}

immutable keycode_table = () {
    KeyCode[256] table;

    with (KeyCode) {
        table[0x30] = Num_0;
        table[0x31] = Num_1;
        table[0x32] = Num_2;
        table[0x33] = Num_3;
        table[0x34] = Num_4;
        table[0x35] = Num_5;
        table[0x36] = Num_6;
        table[0x37] = Num_7;
        table[0x38] = Num_8;
        table[0x39] = Num_9;

        table[0x41] = A;
        table[0x42] = B;
        table[0x43] = C;
        table[0x44] = D;
        table[0x45] = E;
        table[0x46] = F;
        table[0x47] = G;
        table[0x48] = H;
        table[0x49] = I;
        table[0x4A] = J;
        table[0x4B] = K;
        table[0x4C] = L;
        table[0x4D] = M;
        table[0x4E] = N;
        table[0x4F] = O;
        table[0x50] = P;
        table[0x51] = Q;
        table[0x52] = R;
        table[0x53] = S;
        table[0x54] = T;
        table[0x55] = U;
        table[0x56] = V;
        table[0x57] = W;
        table[0x58] = X;
        table[0x59] = Y;
        table[0x5A] = Z;

        //Math
        table[VK_OEM_MINUS] = Minus;
        table[VK_OEM_PLUS] = Equal;

        //Brackets
        table[VK_OEM_4] = LeftBracket;
        table[VK_OEM_6] = RightBracket;

        //Grammatical Characters
        table[VK_OEM_5] = BackSlash;
        table[VK_OEM_1] = Semicolon;
        table[VK_OEM_7] = Apostrophe;
        table[VK_OEM_COMMA] = Comma;
        table[VK_OEM_PERIOD] = Period;
        table[VK_OEM_2] = Slash;
        table[VK_OEM_3] = GraveAccent;
        table[VK_SPACE] = Space;
        table[VK_SHIFT] = Shift;

        //Text Control Keys
        table[VK_BACK] = Backspace;
        table[VK_DELETE] = Delete;
        table[VK_INSERT] = Insert;
        table[VK_TAB] = Tab;
        table[VK_RETURN] = Enter;

        //Arrows
        table[VK_LEFT] = Left;
        table[VK_RIGHT] = Right;
        table[VK_UP] = Up;
        table[VK_DOWN] = Down;

        //Locks
        table[VK_CAPITAL] = CapsLock;
        table[VK_SCROLL] = ScrollLock;
        table[VK_NUMLOCK] = NumLock;

        //Auxiliary
        table[VK_SNAPSHOT] = PrintScreen;
        table[VK_MENU] = Alt;

        table[VK_PRIOR] = PageUp;
        table[VK_NEXT] = PageDown;
        table[VK_END] = End;
        table[VK_HOME] = Home;

        table[VK_ESCAPE] = Escape;
        table[VK_CONTROL] = Control;

        //Function Keys
        table[VK_F1] = F1;
        table[VK_F2] = F2;
        table[VK_F3] = F3;
        table[VK_F4] = F4;
        table[VK_F5] = F5;
        table[VK_F6] = F6;
        table[VK_F7] = F7;
        table[VK_F8] = F8;
        table[VK_F9] = F9;
        table[VK_F10] = F10;
        table[VK_F11] = F11;
        table[VK_F12] = F12;
        table[VK_F13] = F13;
        table[VK_F14] = F14;
        table[VK_F15] = F15;
        table[VK_F16] = F16;
        table[VK_F17] = F17;
        table[VK_F18] = F18;
        table[VK_F19] = F19;
        table[VK_F20] = F20;
        table[VK_F21] = F21;
        table[VK_F22] = F22;
        table[VK_F23] = F23;
        table[VK_F24] = F24;

        //Keypad
        table[VK_NUMPAD0] = Keypad_0;
        table[VK_NUMPAD1] = Keypad_1;
        table[VK_NUMPAD2] = Keypad_2;
        table[VK_NUMPAD3] = Keypad_3;
        table[VK_NUMPAD4] = Keypad_4;
        table[VK_NUMPAD5] = Keypad_5;
        table[VK_NUMPAD6] = Keypad_6;
        table[VK_NUMPAD7] = Keypad_7;
        table[VK_NUMPAD8] = Keypad_8;
        table[VK_NUMPAD9] = Keypad_9;

        table[VK_ADD] = Keypad_Add;
        table[VK_SUBTRACT] = Keypad_Subtract;
        table[VK_MULTIPLY] = Keypad_Multiply;
        table[VK_DIVIDE] = Keypad_Divide;
        table[VK_OEM_PLUS] = Keypad_Enter;

        //Positional Keys
        table[VK_LSHIFT] = LeftShift;
        table[VK_LCONTROL] = LeftControl;
        table[VK_LMENU] = LeftAlt;
        table[VK_LWIN] = LeftSuper;

        table[VK_RSHIFT] = RightShift;
        table[VK_RCONTROL] = RightControl;
        table[VK_RMENU] = RightAlt;
        table[VK_RWIN] = RightSuper;
    }

    return table;
} ();
