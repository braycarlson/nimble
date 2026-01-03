pub const c = @cImport(@cInclude("raylib.h"));

pub const Color = c.Color;
pub const Font = c.Font;
pub const Rectangle = c.Rectangle;
pub const Vector2 = c.Vector2;

pub const init_window = c.InitWindow;
pub const close_window = c.CloseWindow;
pub const window_should_close = c.WindowShouldClose;
pub const set_target_fps = c.SetTargetFPS;
pub const set_config_flags = c.SetConfigFlags;
pub const begin_drawing = c.BeginDrawing;
pub const end_drawing = c.EndDrawing;
pub const clear_background = c.ClearBackground;
pub const get_frame_time = c.GetFrameTime;

pub const draw_rectangle = c.DrawRectangle;
pub const draw_rectangle_rounded = c.DrawRectangleRounded;
pub const draw_rectangle_lines = c.DrawRectangleLines;
pub const draw_line = c.DrawLine;
pub const draw_circle = c.DrawCircle;
pub const draw_triangle = c.DrawTriangle;
pub const draw_text = c.DrawText;
pub const draw_text_ex = c.DrawTextEx;
pub const measure_text = c.MeasureText;
pub const measure_text_ex = c.MeasureTextEx;

pub const load_font_ex = c.LoadFontEx;
pub const unload_font = c.UnloadFont;
pub const set_texture_filter = c.SetTextureFilter;

pub const is_key_pressed = c.IsKeyPressed;
pub const is_key_down = c.IsKeyDown;
pub const is_mouse_button_pressed = c.IsMouseButtonPressed;
pub const is_mouse_button_released = c.IsMouseButtonReleased;
pub const get_mouse_x = c.GetMouseX;
pub const get_mouse_y = c.GetMouseY;
pub const get_mouse_wheel_move = c.GetMouseWheelMove;

pub const is_file_dropped = c.IsFileDropped;
pub const load_dropped_files = c.LoadDroppedFiles;
pub const unload_dropped_files = c.UnloadDroppedFiles;

pub const FLAG_MSAA_4X_HINT = c.FLAG_MSAA_4X_HINT;
pub const TEXTURE_FILTER_BILINEAR = c.TEXTURE_FILTER_BILINEAR;

pub const KEY_SPACE = c.KEY_SPACE;
pub const KEY_LEFT = c.KEY_LEFT;
pub const KEY_RIGHT = c.KEY_RIGHT;
pub const KEY_UP = c.KEY_UP;
pub const KEY_DOWN = c.KEY_DOWN;
pub const KEY_HOME = c.KEY_HOME;
pub const KEY_END = c.KEY_END;
pub const KEY_LEFT_SHIFT = c.KEY_LEFT_SHIFT;
pub const KEY_ONE = c.KEY_ONE;
pub const KEY_TWO = c.KEY_TWO;
pub const KEY_THREE = c.KEY_THREE;

pub const MOUSE_BUTTON_LEFT = c.MOUSE_BUTTON_LEFT;
