#pragma once
#include <cstdint>
#include <functional>
#include <string>

namespace isolyn {

// A single domino tile from a standard Double-Six set. A tile is defined
// by its two pip values (0-6 each) and is orientation-independent as an
// identity: the tile bearing 5 and 0 is the same physical tile whether
// referred to as "5-0" or "0-5". Which face points which direction once a
// tile is placed on the board is a property of a Move, not of the tile's
// identity -- this type only ever represents the tile itself.
//
// Every tile carries a dense canonical index in [0, 27] via the standard
// triangular-number ordering for a Double-Six set (low <= high):
//   index(low, high) = high*(high+1)/2 + low
// Deriving this once here, with a tested inverse (fromIndex), means
// Zobrist hashing, transposition-table lookups, and bitset-based state
// representations introduced later never have to re-derive or duplicate
// this mapping -- they just index into it.
class DominoTile {
public:
    // Trivial default construction keeps stack-allocated search buffers free
    // of per-entry initialization; callers must assign before reading.
    DominoTile() = default;

    static constexpr int kMinPips = 0;
    static constexpr int kMaxPips = 6;
    static constexpr int kTileCount = 28; // (kMaxPips+1)*(kMaxPips+2)/2

    // Constructs the tile identified by two pip values, in either order.
    constexpr DominoTile(int sideA, int sideB) noexcept
        : m_low(static_cast<std::int8_t>(sideA < sideB ? sideA : sideB)),
          m_high(static_cast<std::int8_t>(sideA < sideB ? sideB : sideA)) {}

    constexpr int low() const noexcept { return m_low; }
    constexpr int high() const noexcept { return m_high; }
    constexpr int value() const noexcept { return m_low + m_high; }

    constexpr bool isDouble() const noexcept { return m_low == m_high; }

    // Dense identity in [0, kTileCount).
    constexpr int index() const noexcept {
        return m_high * (m_high + 1) / 2 + m_low;
    }

    // Reconstructs a tile from its dense index. Exact inverse of index().
    static constexpr DominoTile fromIndex(int index) noexcept {
        int high = 0;
        while ((high + 1) * (high + 2) / 2 <= index) {
            ++high;
        }
        int low = index - high * (high + 1) / 2;
        return DominoTile(low, high);
    }

    constexpr bool operator==(const DominoTile& other) const noexcept {
        return m_low == other.m_low && m_high == other.m_high;
    }
    constexpr bool operator!=(const DominoTile& other) const noexcept {
        return !(*this == other);
    }

    // Whether this tile has a face matching the given pip value -- used by
    // move generation to test whether a tile can legally sit against an
    // open end showing that value.
    constexpr bool hasFace(int pipValue) const noexcept {
        return m_low == pipValue || m_high == pipValue;
    }

    // Human-readable form ("5-0") for logging, diagnostics, and the
    // eventual explanation engine.
    std::string describe() const;

private:
    std::int8_t m_low;
    std::int8_t m_high;
};

} // namespace isolyn

namespace std {
template <>
struct hash<isolyn::DominoTile> {
    std::size_t operator()(const isolyn::DominoTile& tile) const noexcept {
        return static_cast<std::size_t>(tile.index());
    }
};
} // namespace std
