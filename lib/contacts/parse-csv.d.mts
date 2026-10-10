/** Parse an RFC 4180 CSV into rows with a configurable safety limit. */
export function parseCsv(input: string, options?: {maxRows?: number; maxColumns?: number}): string[][];
/** Normalize E.164 or optionally convert common Nigerian mobile patterns. */
export function normalizePhone(input: unknown, defaultCountry?: 'none' | 'NG'): string;
