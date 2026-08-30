/// An incremental fragment of a tool call that is still being streamed.
///
/// Backends that stream tool calls send the tool's name first and its arguments
/// in fragments afterwards. A delta carries whichever parts arrived in a single
/// stream event, so consumers can react the moment a call begins instead of
/// waiting for it to finish.
///
/// A delta is **never executable**. Its [argumentsDelta] is one fragment of a
/// JSON document that only parses once every fragment has been concatenated —
/// the complete, runnable call still arrives on `LLMChunkMessage.toolCalls`
/// when the backend signals the call is finished.
class LLMToolCallDelta {
  /// Creates a fragment of a streamed tool call.
  const LLMToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });

  /// Which tool call within the current turn this fragment belongs to.
  ///
  /// This is the only field every backend sets on every fragment, so it is the
  /// key to correlate fragments with each other and with the completed call.
  final int index;

  /// Provider-assigned id, set on the first fragment for this [index] only.
  final String? id;

  /// The tool's name, set on the first fragment for this [index] only.
  ///
  /// This is the field that makes streaming worth doing: it is known from the
  /// very first event, long before the arguments finish arriving.
  final String? name;

  /// The argument fragment carried by *this* event — not the accumulation.
  ///
  /// `null` when the event carried no argument text, which is the normal shape
  /// of a first fragment that announces [id] and [name].
  final String? argumentsDelta;

  @override
  String toString() =>
      'LLMToolCallDelta(index: $index, id: $id, name: $name, '
      'argumentsDelta: $argumentsDelta)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LLMToolCallDelta &&
          other.index == index &&
          other.id == id &&
          other.name == name &&
          other.argumentsDelta == argumentsDelta;

  @override
  int get hashCode => Object.hash(index, id, name, argumentsDelta);
}
