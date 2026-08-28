/// Width breakpoints for the phone/web shell, all measured against
/// `MediaQuery.sizeOf(context).width`.
///
/// Width rather than platform, because width is the actual constraint: a narrow
/// window on a laptop should look like a phone, and a tablet in landscape should
/// not have to lie about what it is. "Is there a mouse" and "is this an
/// installed window" are different questions with different answers.
library;

/// At or above this there is room for the navigation to sit *beside* the
/// content. The bottom bar exists because thumbs reach the bottom of a phone; on
/// a desktop that is the furthest point from the eye and costs a full-width strip.
const double sidebarBreakpoint = 640.0;

/// The sidebar's own width. Enough for the longest destination label at the
/// size the bottom bar already sets, plus the app controls at its foot.
const double sidebarWidth = 180.0;

/// Centred cap for the screens that stay a single column. A report bar as wide
/// as a monitor and sixteen pixels tall is not a report — past about this width
/// a row's duration has flown away from the label it belongs to.
const double contentMaxWidth = 800.0;
