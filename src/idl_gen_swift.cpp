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
    for (const auto& kw : swiftKeywords) {
      keywords_.insert(kw);
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
    code += "import Foundation\n";
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
        default:
          assert("tried to retrieve unknown type, a new case must be required");
          return "";
    }
  }

  void GenStruct(const StructDef &struct_def, std::string *code_ptr) {
    GenComment(struct_def.doc_comment, code_ptr, nullptr);

    std::string &code = *code_ptr;

    code += "struct ";
    code += struct_def.name;
    code += ": Table";
    code += " {\n";

    // Add book keeping variables from Table protocol
    code += "    var data: Data\n";

    code += "    var tablePosition: UOffset = 0\n";

    code += "\n";

    // add struct constructor for parsing
    code += "    init(data: Data) {";
    code += " self.data = Data ";
    code += "}\n\n";

    // Generate struct fields accessors
    for (auto it : struct_def.fields.vec) {
      auto& field = *it;

      if (field.deprecated) continue;

      if (!field.doc_comment.empty()) {
        code += "\n";
        GenComment(field.doc_comment, code_ptr, nullptr, "    ");
      }

      // TODO: Make var getters work for properties that are not ints
      code += "    public var ";
      code += MakeCamel(field.name, false);

      code += ": ";

      code += GenType(field.value.type);


      code += " {\n";
      code += "        get {\n";
      code += "            let tableValue = offset(vtableElementIndex: ";
      code += NumToString(field.value.offset);
      code += ") \n";
      code += "            return tableValue != 0 ? data.getIntegerType(uoffset:tableValue + tablePosition) : ";
      code += field.value.constant;
      code += "\n";
      code += "        }\n";
      code += "    }\n";
    }

    // Generate a table constructor of the form:
    // public static int createName(FlatBufferBuilder builder, args...)
    code += "\n    public static func ";
    code += "create" + struct_def.name;
    code += "(builder: Builder";
    for (auto it = struct_def.fields.vec.begin();
         it != struct_def.fields.vec.end(); ++it) {
      auto &field = **it;
      if (field.deprecated) continue;
      code += ",\n                                ";
      code += field.name;
      code += ": ";
      code += GenType(field.value.type);
      if (!IsScalar(field.value.type.base_type)) code += "UOffset";
    }

    code += ") -> UOffset {\n        builder.";
    code += "startObject(feildCount: ";
    code += NumToString(struct_def.fields.vec.size()) + ")\n";
    for (size_t size = struct_def.sortbysize ? sizeof(largest_scalar_t) : 1;
         size; size /= 2) {
      for (auto it = struct_def.fields.vec.rbegin();
           it != struct_def.fields.vec.rend(); ++it) {
        auto &field = **it;
        if (!field.deprecated &&
            (!struct_def.sortbysize ||
                size == SizeOf(field.value.type.base_type))) {
          code += "        " + struct_def.name + ".";
          code += "add";
          code += MakeCamel(field.name) + "(builder, " + field.name;
          if (!IsScalar(field.value.type.base_type)) code += "Offset";
          code += ")\n";
        }
      }
    }
    code += "        return " + struct_def.name + ".";
    code += "end" + struct_def.name;
    code += "(builder)\n    }\n\n";

    generateClassStructStaticMethods(struct_def, code_ptr);
  }

  void generateClassStructStaticMethods(const StructDef &struct_def, std::string *code_ptr) {

    std::string &code = *code_ptr;
    // Generate a set of static methods that allow table construction,
    // of the form:
    // public static func addName(_ builder: Builder, _ value: Int32)
    // { builder.add(vTableIndex: 0, value: value, defaultValue: 100) }
    // Unlike the Create function, these always work.
    code += "    public static func start";
    code += struct_def.name;
    code += "(builder: Builder) { builder.";
    code += "startObject(feildCount: ";
    code += NumToString(struct_def.fields.vec.size()) + ") }\n";
    for (auto it = struct_def.fields.vec.begin();
         it != struct_def.fields.vec.end(); ++it) {
      auto &field = **it;
      if (field.deprecated) continue;
      code += "    public static func add";
      code += MakeCamel(field.name);
      code += "(_ builder: Builder, ";
      auto argname = MakeCamel(field.name, false);
      if (!IsScalar(field.value.type.base_type)) argname += "Offset";
      code += "_ " + argname + ": " + GenType(field.value.type) + ") { builder." + "add";
      code += "(vTableIndex: ";
      code += NumToString(it - struct_def.fields.vec.begin()) + ", " + argname + ": ";
      code += argname;
      code += ", defaultValue: ";
      code += field.value.constant;
      code += ") }\n";

      // TODO: add code for generating vectos in table
    }
    code += "    public static func ";
    code += "end" + struct_def.name;
    code += "(_ builder: Builder) -> UOffset {\n        let o = builder.";
    code += "endObject()\n";
    for (auto it = struct_def.fields.vec.begin();
         it != struct_def.fields.vec.end(); ++it) {
      auto &field = **it;
      if (!field.deprecated && field.required) {
        code += "    builder.required(o, ";
        code += NumToString(field.value.offset);
        code += ")  // " + field.name + "\n";
      }
    }
    code += "        return o\n    }\n";
    if (parser_.root_struct_def_ == &struct_def) {
        code += "    public static func ";
        code += "finish" + struct_def.name;
        code += "Buffer(builder: Builder, offset: UOffset) {";
        code += " builder.finish(rootTable: offset";

        if (parser_.file_identifier_.length()) {
          code += ", \"" + parser_.file_identifier_ + "\"";
        }
        code += ") }\n";
    }
  // Only generate key compare function for table,
  // because `key_field` is not set for struct
  if (struct_def.has_key && !struct_def.fixed) {
    code += "\n  protected int keysCompare(";
    code += "Integer o1, Integer o2, ByteBuffer _bb) {";

    code += " }\n";

    code += "\n  public static " + struct_def.name;
    code += " __lookup_by_key(";
    code += "int vectorLocation, ";

    code += " key, ByteBuffer bb) {\n";

    code += "    int span = ";
    code += "bb.GetInt(vectorLocation - 4)\n";
    code += "    var start: UOffset = 0\n";
    code += "    while (span != 0) {\n";
    code += "      int middle = span / 2;\n";
    code += "      if (comp > 0) {\n";
    code += "        span = middle;\n";
    code += "      } else if (comp < 0) {\n";
    code += "        middle++;\n";
    code += "        start += middle;\n";
    code += "        span -= middle;\n";
    code += "      } else {\n";
    code += "        return ";
    code += ".__assign(tableOffset, bb);\n";
    code += "      }\n    }\n";
    code += "    return null;\n";
    code += "  }\n";
  }
  code += "}";
  code += "\n\n";
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

