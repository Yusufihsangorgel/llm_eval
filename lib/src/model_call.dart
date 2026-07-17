/// Signature of a function that sends [prompt] to a language model and
/// returns the raw text of its response.
///
/// The harness does not ship a model client. Bind this to whatever you
/// already use: an OpenAI or Anthropic SDK call, a local Ollama HTTP
/// request, or a canned fake in tests.
///
/// The harness sends a single user prompt per call. If your model needs
/// a system prompt or conversation history, encode it in your binding.
typedef ModelCall = Future<String> Function(String prompt);
