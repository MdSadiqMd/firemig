export interface BackoffOptions {
    initialMs?: number;
    maximumMs?: number;
    factor?: number;
    jitter?: number;
    random?: () => number;
}

export function backoffDelay(attempt: number, options: BackoffOptions = {}): number {
    const initial = options.initialMs ?? 100;
    const maximum = options.maximumMs ?? 5_000;
    const factor = options.factor ?? 2;
    const jitter = options.jitter ?? 0.2;
    const random = options.random ?? Math.random;
    const base = Math.min(maximum, initial * factor ** Math.max(0, attempt));
    return Math.max(0, Math.round(base * (1 - jitter + random() * jitter * 2)));
}

export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
    return new Promise((resolve, reject) => {
        if (signal?.aborted === true) return reject(signal.reason);
        const delay = AbortSignal.timeout(Math.max(0, ms));
        const cleanup = () => {
            delay.removeEventListener("abort", finish);
            signal?.removeEventListener("abort", onAbort);
        };
        const finish = () => {
            cleanup();
            resolve();
        };
        const onAbort = () => {
            cleanup();
            reject(signal?.reason);
        };
        delay.addEventListener("abort", finish, { once: true });
        signal?.addEventListener("abort", onAbort, { once: true });
    });
}
