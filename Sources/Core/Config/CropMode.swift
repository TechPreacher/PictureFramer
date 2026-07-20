/// What the exported crop contains: the framed picture plus a strip of
/// wall (margin applies), or just the painting inside the frame (margin
/// is meaningless and forced to zero).
enum CropMode: String, CaseIterable, Sendable {
    case framed
    case paintingOnly
}
