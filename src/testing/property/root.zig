pub const exhaustigen = @import("exhaustigen.zig");
pub const properties = @import("properties.zig");
pub const invariant = @import("invariant.zig");

pub const Gen = exhaustigen.Gen;
pub const Invariant = invariant.Invariant;
pub const InvariantContext = invariant.Context;

pub const property_keyboard_keydown_is_down = properties.property_keyboard_keydown_is_down;
pub const property_keyboard_keyup_not_down = properties.property_keyboard_keyup_not_down;
pub const property_keyboard_clear_empty = properties.property_keyboard_clear_empty;
pub const property_modifier_set_flags = properties.property_modifier_set_flags;
pub const property_modifier_set_total = properties.property_modifier_set_total;
pub const property_modifier_set_equality = properties.property_modifier_set_equality;
pub const property_binding_match_self = properties.property_binding_match_self;
pub const property_binding_id_unique = properties.property_binding_id_unique;
pub const property_response_validity = properties.property_response_validity;
pub const property_keyboard_modifier_tracking = properties.property_keyboard_modifier_tracking;
pub const property_keyboard_modifier_tracking_ctrl = properties.property_keyboard_modifier_tracking_ctrl;
pub const property_keyboard_modifier_tracking_alt = properties.property_keyboard_modifier_tracking_alt;

pub const check_all_invariants = invariant.check_all;
pub const keyboard_invariants = invariant.keyboard_invariants;

test {
    _ = exhaustigen;
    _ = invariant;
    _ = properties;
}
