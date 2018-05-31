#include "flatbuffers/code_generators.h"
#include "flatbuffers/flatbuffers.h"
#include "flatbuffers/idl.h"

#include <string>

namespace flatbuffers {

static std::string GeneratedFileName(const std::string &path,
                                     const std::string &file_name) {
  return path + file_name + "_generated.swift";
}

namespace swift {


// Iterate through all definitions we haven't generated code for (enums, structs,
// and tables) and output them to a single file.
class SwiftGenerator : public BaseGenerator {
 public:
  SwiftGenerator(const Parser &parser, const std::string &path, const std::string &file_name)
      : BaseGenerator(parser, path, file_name, "" /* not used */, "" /* not used */){
    const char *swiftKeywords[] = { "associatedtype",
                                    "class",
                                    "deinit",
                                    "enum",
                                    "extension",
                                    "fileprivate",
                                    "func",
                                    "import",
                                    "init",
                                    "inout",
                                    "internal",
                                    "let",
                                    "open",
                                    "operator",
                                    "private",
                                    "protocol",
                                    "public",
                                    "static",
                                    "struct",
                                    "subscript",
                                    "typealias",
                                    "var",
                                    "break",
                                    "case",
                                    "continue",
                                    "default",
                                    "defer",
                                    "do",
                                    "else",
                                    "fallthrough",
                                    "for",
                                    "guard",
                                    "if",
                                    "in",
                                    "repeat",
                                    "return",
                                    "switch",
                                    "where",
                                    "while",
                                    "as",
                                    "Any",
                                    "catch",
                                    "false",
                                    "is",
                                    "nil",
                                    "rethrows",
                                    "super",
                                    "self",
                                    "Self",
                                    "throw",
                                    "throws",
                                    "true",
                                    "try",
                                    "_",
                                    "associativity",
                                    "convenience",
                                    "dynamic",
                                    "didSet",
                                    "final",
                                    "get",
                                    "infix",
                                    "indirect",
                                    "lazy",
                                    "left",
                                    "mutating",
                                    "none",
                                    "nonmutating",
                                    "optional",
                                    "override",
                                    "postfix",
                                    "precedence",
                                    "prefix",
                                    "Protocol",
                                    "required",
                                    "right",
                                    "set",
                                    "Type",
                                    "unowned",
                                    "weak",
                                    "willSet"};
    for (auto kw = swiftKeywords; *kw; kw++) {
      keywords_.insert(*kw);
    }
  }

  bool generate() {
    std::string one_file_code ;

    // Generate code for all the enum declarations.
    for (auto it = parser_.enums_.vec.begin(); it != parser_.enums_.vec.end(); ++it) {
      std::string declcode;
      const auto &enum_def = **it;
      if (!enum_def.generated) {
        GenEnum(enum_def, parser_, &declcode);
        std::cout << declcode << "\n --------------------- \n \n \n" << std::endl;
      }

      if (parser_.opts.one_file) {
        one_file_code += declcode;
      } else {
        if (!SaveType(**it, declcode)) return false;
      }
    }

    // Generate Swift code for structs
    for (auto it = parser_.structs_.vec.begin(); it != parser_.structs_.vec.end(); ++it) {

      std::string declcode;
      GenStruct(**it, &declcode);
      if (parser_.opts.one_file) {
        one_file_code += declcode;
      } else {
        if (!SaveType(**it, declcode)) return false;
      }
    }

    // Generate single-file output
    if (parser_.opts.one_file) {
      std::string code = "";
      BeginFile(LastNamespacePart(swift_namespace_), &code);
      code += one_file_code;

      const std::string filename = GeneratedFileName(path_, file_name_);
      return SaveFile(filename.c_str(), code, false);
    }
    return true;
  }

  std::string EscapeKeyword(const std::string &name) const {
    return keywords_.find(name) == keywords_.end() ? name : name + "_";
  }

  std::string Name(const Definition &def) const {
    return EscapeKeyword(def.name);
  }

  std::string Name(const EnumVal &ev) const { return EscapeKeyword(ev.name); }

 private:
  Namespace swift_namespace_;

  std::set<std::string> keywords_;

  void BeginFile(const std::string name_space_name, std::string *code_ptr) {
    std::string &code = *code_ptr;
    code = code + "// " + FlatBuffersGeneratedWarning() + "\n\n";
    code += "import FlatBuffers\n\n";
  }

  // Save out the generated code for a Swift Table type.
  bool SaveType(const Definition &def, const std::string &classcode) {
    if (!classcode.length()) {
      return true;
    }

    Namespace &ns = swift_namespace_.components.empty() ? *def.defined_namespace
                                                    : swift_namespace_;
    std::string code;

    BeginFile(LastNamespacePart(ns), &code);
    code += classcode;
    std::string filename = NamespaceDir(ns) + def.name + ".swift";
    return SaveFile(filename.c_str(), code, false);
  }

  // Return a Swift type from the table in idl.h
  std::string GenType(const Type &type) const {
      switch (type.base_type) {
        case BASE_TYPE_NONE:
          return "Void";
        case BASE_TYPE_UTYPE:
          return "Void";
        case BASE_TYPE_BOOL:
          return "Bool";
        case BASE_TYPE_CHAR:
          return "Int8";
        case BASE_TYPE_UCHAR:
          return "UInt8";
        case BASE_TYPE_SHORT:
          return "Int16";
        case BASE_TYPE_USHORT:
          return " UInt16";
        case BASE_TYPE_INT:
          return "Int32";
        case BASE_TYPE_UINT:
          return "UInt32";
        case BASE_TYPE_LONG:
          return "Int64";
        case BASE_TYPE_ULONG:
          return "UInt64";
        case BASE_TYPE_FLOAT:
          return "Float";
        case BASE_TYPE_DOUBLE:
          return "Double";
        case BASE_TYPE_STRING:
          return "String";
        case BASE_TYPE_VECTOR: {
          const auto type_name = GenType(type.VectorType());
          return "Array<" + type_name + ">";
        }

        case BASE_TYPE_STRUCT:
          return "Never";

        case BASE_TYPE_UNION:
          return "Never";
    }
  }

  void GenStruct(const StructDef &struct_def, std::string *code_ptr) {
    GenComment(struct_def.doc_comment, code_ptr, nullptr);

    std::string &code = *code_ptr;

    code += "protocol ";
    code += struct_def.name;
    code += " {\n";

    // Generate struct fields accessors
    for (auto it : struct_def.fields.vec) {
      auto& field = *it;

      if (field.deprecated) continue;

      if (!field.doc_comment.empty()) {
        code += "\n";
        GenComment(field.doc_comment, code_ptr, nullptr, "    ");
      }

      code += "    var ";
      code += MakeCamel(field.name, false);

      code += ": ";

      code += GenType(field.value.type);

      code += " { get }\n";
    }

    code += "}\n\n";
  }

  // Return a Swift type from the table in idl.h
  std::string GenTypeBasic(const Type &type, bool user_facing_type) const {
    static const char *ctypename[] = {
        // clang-format off
#define FLATBUFFERS_TD(ENUM, IDLTYPE, CTYPE, JTYPE, GTYPE, NTYPE, PTYPE, STYPE) \
            #CTYPE,
        FLATBUFFERS_GEN_TYPES(FLATBUFFERS_TD)
#undef FLATBUFFERS_TD
        // clang-format on
    };
    if (user_facing_type) {
      if (type.enum_def) return WrapInNameSpace(*type.enum_def);
      if (type.base_type == BASE_TYPE_BOOL) return "bool";
    }
    return ctypename[type.base_type];
  }

  // Generate an enum declaration,
  // an enum string lookup table,
  // and an enum array of values
  void GenEnum(const EnumDef &enum_def, const Parser &parser, std::string *code_ptr) {
    std::string &code = *code_ptr;

    GenComment(enum_def.doc_comment, code_ptr, nullptr);
    code += "enum " +  Name(enum_def) + ": Int";
    code += " {\n";

    int64_t anyv = 0;
    const EnumVal *minv = nullptr, *maxv = nullptr;
    for (auto it = enum_def.vals.vec.begin(); it != enum_def.vals.vec.end(); ++it) {
      const auto &ev = **it;

      code += "\t case " + ev.name + " = " + NumToString(ev.value) + "\n";

      minv = !minv || minv->value > ev.value ? &ev : minv;
      maxv = !maxv || maxv->value < ev.value ? &ev : maxv;
      anyv |= ev.value;
    }
    code += "}\n";
  }
};

} // namespace swift

bool GenerateSwift(const Parser &parser,
                    const std::string &path,
                    const std::string &file_name) {
  swift::SwiftGenerator generator(parser, path, file_name);
  return generator.generate();
}

}  // namespace flatbuffers

