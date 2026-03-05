/**
 * Utility functions for comparing spoken words with expected words
 * Used in the vocabulary quiz to determine if pronunciation is correct
 */

/**
 * Removes accents from Spanish characters
 */
function removeAccents(str: string): string {
  return str.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

/**
 * Normalizes a word for comparison
 * - Lowercase
 * - Remove leading/trailing punctuation
 * - Optionally remove accents
 */
export function normalizeWord(word: string, options?: { ignoreAccents?: boolean }): string {
  let normalized = word.toLowerCase().trim();

  // Remove leading/trailing punctuation (but keep internal punctuation like hyphens)
  normalized = normalized.replace(/^[¡¿!"'.,;:]+|[!"'.,;:?!]+$/g, '');

  if (options?.ignoreAccents) {
    normalized = removeAccents(normalized);
  }

  return normalized;
}

/**
 * Calculate Levenshtein distance between two strings
 * Used for fuzzy matching
 */
function levenshteinDistance(a: string, b: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1, // substitution
          matrix[i][j - 1] + 1,     // insertion
          matrix[i - 1][j] + 1      // deletion
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Calculate similarity score between two strings (0-1)
 */
function calculateSimilarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length === 0 || b.length === 0) return 0;

  const distance = levenshteinDistance(a, b);
  const maxLength = Math.max(a.length, b.length);
  return 1 - distance / maxLength;
}

export interface ComparisonResult {
  isMatch: boolean;
  similarity: number;
  normalizedSpoken: string;
  normalizedExpected: string;
  exactMatch: boolean;
}

export interface CompareOptions {
  ignoreAccents?: boolean;
  fuzzyThreshold?: number;  // Similarity threshold (0-1), default 0.8
}

/**
 * Compare spoken word with expected word
 * Returns match result with similarity score
 */
export function compareWords(
  spoken: string,
  expected: string,
  options?: CompareOptions
): ComparisonResult {
  const { ignoreAccents = true, fuzzyThreshold = 0.8 } = options || {};

  const normalizedSpoken = normalizeWord(spoken, { ignoreAccents });
  const normalizedExpected = normalizeWord(expected, { ignoreAccents });

  const exactMatch = normalizedSpoken === normalizedExpected;
  const similarity = calculateSimilarity(normalizedSpoken, normalizedExpected);
  const isMatch = exactMatch || similarity >= fuzzyThreshold;

  return {
    isMatch,
    similarity,
    normalizedSpoken,
    normalizedExpected,
    exactMatch,
  };
}

/**
 * Check if the spoken text contains the expected word
 * Useful when user speaks a full sentence instead of just the word
 */
export function containsWord(spokenText: string, expectedWord: string, options?: CompareOptions): boolean {
  const { ignoreAccents = true, fuzzyThreshold = 0.8 } = options || {};

  const normalizedExpected = normalizeWord(expectedWord, { ignoreAccents });
  const words = spokenText.split(/\s+/);

  for (const word of words) {
    const normalizedWord = normalizeWord(word, { ignoreAccents });
    const similarity = calculateSimilarity(normalizedWord, normalizedExpected);
    if (similarity >= fuzzyThreshold) {
      return true;
    }
  }

  return false;
}
