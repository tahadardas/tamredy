export const requiredMigrations: readonly string[];
export function missingMigrations(applied: Iterable<string>): string[];
