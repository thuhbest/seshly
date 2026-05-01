"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.calendarColors = void 0;
exports.normalizeEventType = normalizeEventType;
exports.calendarColors = {
    class: { colorKey: 'blue', colorHex: 0x3b82f6 },
    test: { colorKey: 'orange', colorHex: 0xf97316 },
    exam: { colorKey: 'red', colorHex: 0xef4444 },
    tutorial: { colorKey: 'green', colorHex: 0x10b981 },
    tutoring: { colorKey: 'purple', colorHex: 0x8b5cf6 },
    meeting: { colorKey: 'purple', colorHex: 0x7c3aed },
};
function normalizeEventType(value) {
    const raw = String(value || '').toLowerCase();
    if (raw === 'exam')
        return 'exam';
    if (raw === 'test')
        return 'test';
    if (raw === 'tutorial')
        return 'tutorial';
    if (raw === 'tutoring')
        return 'tutoring';
    if (raw === 'meeting')
        return 'meeting';
    return 'class';
}
