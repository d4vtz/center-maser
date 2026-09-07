import test from "node:test";
import assert from "node:assert/strict";

import {
    chooseInsertionSide,
    calculateWeightedHeights,
    resizeWeightPair,
    wrappedIndex
} from "./layout-core.mjs";

test("balanced insertion fills the shorter stack", () => {
    assert.equal(
        chooseInsertionSide({ leftCount: 1, rightCount: 2 }),
        "left"
    );

    assert.equal(
        chooseInsertionSide({ leftCount: 3, rightCount: 1 }),
        "right"
    );
});

test("balanced insertion uses nextSide on ties", () => {
    assert.equal(
        chooseInsertionSide({
            leftCount: 2,
            rightCount: 2,
            nextSide: "left"
        }),
        "left"
    );
});

test("explicit insertion policies override balancing", () => {
    assert.equal(
        chooseInsertionSide({
            policy: "right",
            leftCount: 0,
            rightCount: 5
        }),
        "right"
    );

    assert.equal(
        chooseInsertionSide({
            policy: "focused-stack",
            focusedZone: "left",
            leftCount: 4,
            rightCount: 0
        }),
        "left"
    );
});

test("weighted stack preserves usable height", () => {
    const heights = calculateWeightedHeights([1, 2, 1], 1000, 10);
    const usable = 980;

    assert.ok(Math.abs(heights.reduce((a, b) => a + b, 0) - usable) < 1e-9);
    assert.ok(Math.abs(heights[1] - 490) < 1e-9);
});

test("vertical resize transfers weight without changing total", () => {
    const pair = resizeWeightPair(1, 1, 0.1);

    assert.deepEqual(pair, [1.1, 0.9]);
    assert.equal(pair[0] + pair[1], 2);
});

test("vertical resize respects minimum weight", () => {
    assert.equal(
        resizeWeightPair(0.2, 1.8, -0.1, 0.2),
        null
    );
});

test("focus wrapping is optional", () => {
    assert.equal(wrappedIndex(0, 3, -1, false), 0);
    assert.equal(wrappedIndex(0, 3, -1, true), 2);
    assert.equal(wrappedIndex(2, 3, 1, true), 0);
});
