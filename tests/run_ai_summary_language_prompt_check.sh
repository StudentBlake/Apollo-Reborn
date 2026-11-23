#!/bin/sh
set -eu

# Every summary request names the summary language twice: leading the
# instructions ("You MUST respond in English.") and again after the text
# ("Write the summary in English."). The backend router applies the closing
# line to direct on-device and cloud requests, and uses the on-device language
# when a cloud request falls back to FoundationModels.

test_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$test_root/src/ApolloAISummary.xm"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

require_count() {
    pattern=$1
    expected=$2
    description=$3
    actual=$(grep -F -c "$pattern" "$source_file" || true)
    [ "$actual" -eq "$expected" ] || fail "$description (expected $expected, found $actual)"
}

# All three generation paths (post, link/article/post-and-link, comments) still
# pass through the backend router.
require_count 'ApolloAISummarizeWithBackends(text, request.identifier' 1 \
    'link/article summaries use the backend router'
require_count 'ApolloAISummarizeWithBackends(postText,' 1 \
    'post summaries use the backend router'
require_count 'ApolloAISummarizeWithBackends(commentPrompt,' 1 \
    'comment summaries use the backend router'
grep -F -q 'ApolloAIPromptInSummaryLanguage(text)' "$source_file" ||
    fail 'cloud summaries close with the selected summary language'
grep -F -q 'ApolloAIPromptInSummaryLanguage(fmText)' "$source_file" ||
    fail 'direct on-device summaries close with the selected summary language'
grep -F -q 'ApolloAIPromptInLanguage(fmText, fmLanguage)' "$source_file" ||
    fail 'cloud fallback closes with the on-device-supported language'

# The closing line uses the shared language-name helper and leaves the text
# alone when no language is named.
require_count 'static NSString *ApolloAISummaryLanguageName(NSString *language)' 1 \
    'language names use one shared helper'
require_count 'NSString *name = ApolloAISummaryLanguageName(language);' 2 \
    'instructions and prompt use the shared language name'
grep -F -q 'if (name.length == 0 || text.length == 0) return text;' "$source_file" ||
    fail 'no summary language leaves the text unchanged'
grep -F -q '@"%@\n\nWrite the summary in %@."' "$source_file" ||
    fail 'the text ends with the summary language line'

# On-device summaries cached under the old prompt regenerate once; the profile
# without a language is unchanged.
grep -F -q 'static NSString *const kApolloAIOnDevicePromptRevision = @"2";' "$source_file" ||
    fail 'on-device prompt revision is declared'
grep -F -q '[NSString stringWithFormat:@"apple|%@|%@", language, kApolloAIOnDevicePromptRevision]' "$source_file" ||
    fail 'on-device profile carries the prompt revision'
grep -F -q ': @"apple|";' "$source_file" ||
    fail 'on-device profile without a language stays "apple|"'

echo "ai_summary_language_prompt_check passed"
