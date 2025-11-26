// Polyfills for older WebViews (e.g. Android 11 / Chrome 91)

// Object.groupBy (ES2024) - Chrome 117+
if (!Object.groupBy) {
    Object.groupBy = function (iterable, callback) {
        const result = Object.create(null);
        let i = 0;
        for (const item of iterable) {
            const key = callback(item, i++);
            const keyStr = String(key);
            if (!(keyStr in result)) {
                result[keyStr] = [];
            }
            result[keyStr].push(item);
        }
        return result;
    };
}

// Map.groupBy (ES2024) - Chrome 117+
if (!Map.groupBy) {
    Map.groupBy = function (iterable, callback) {
        const result = new Map();
        let i = 0;
        for (const item of iterable) {
            const key = callback(item, i++);
            if (!result.has(key)) {
                result.set(key, []);
            }
            result.get(key).push(item);
        }
        return result;
    };
}

// Array.prototype.at (ES2022) - Chrome 92+
if (!Array.prototype.at) {
    Array.prototype.at = function (n) {
        n = Math.trunc(n) || 0;
        if (n < 0) n += this.length;
        if (n < 0 || n >= this.length) return undefined;
        return this[n];
    };
}

// String.prototype.at (ES2022) - Chrome 92+
if (!String.prototype.at) {
    String.prototype.at = function (n) {
        n = Math.trunc(n) || 0;
        if (n < 0) n += this.length;
        if (n < 0 || n >= this.length) return undefined;
        return this[n];
    };
}

// Array.prototype.findLast (ES2023) - Chrome 97+
if (!Array.prototype.findLast) {
    Array.prototype.findLast = function (callback, thisArg) {
        for (let i = this.length - 1; i >= 0; i--) {
            const value = this[i];
            if (callback.call(thisArg, value, i, this)) {
                return value;
            }
        }
        return undefined;
    };
}

// Array.prototype.findLastIndex (ES2023) - Chrome 97+
if (!Array.prototype.findLastIndex) {
    Array.prototype.findLastIndex = function (callback, thisArg) {
        for (let i = this.length - 1; i >= 0; i--) {
            const value = this[i];
            if (callback.call(thisArg, value, i, this)) {
                return i;
            }
        }
        return -1;
    };
}

// Promise.withResolvers (ES2024) - Chrome 119+
if (!Promise.withResolvers) {
    Promise.withResolvers = function () {
        let resolve, reject;
        const promise = new Promise((res, rej) => {
            resolve = res;
            reject = rej;
        });
        return { promise, resolve, reject };
    };
}

