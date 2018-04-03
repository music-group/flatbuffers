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


// Iterate through all definitions we haven't generate code for (enums, structs,
// and tables) and output them to a single file.
class SwiftGenerator : public BaseGenerator {
 public:
  SwiftGenerator(const Parser &parser, const std::string &path,
                  const std::string &file_name)
      : BaseGenerator(parser, path, file_name, "" /* not used */,
                      "" /* not used */){};

  bool generate() {
    std::string one_file_code;

    // Generate Swift code for structs
    for (auto it = parser_.structs_.vec.begin();
        it != parser_.structs_.vec.end(); ++it) {

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

 private:
  Namespace swift_namespace_;

  void BeginFile(const std::string name_space_name, std::string *code_ptr) {
    std::string &code = *code_ptr;
    code = code + "// " + FlatBuffersGeneratedWarning() + "\n\n";
    code += "import FlatBuffers\n\n";
  }

  // Save out the generated code for a Go Table type.
  bool SaveType(const Definition &def, const std::string &classcode) {
    if (!classcode.length()) return true;

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
    /*
    static const char *ctypename[] = {
    // clang-format off
    #define FLATBUFFERS_TD(ENUM, IDLTYPE, CTYPE, JTYPE, GTYPE, NTYPE, PTYPE, STYPE) \
            #STYPE,
        FLATBUFFERS_GEN_TYPES(FLATBUFFERS_TD)
    #undef FLATBUFFERS_TD
      // clang-format on
    };
    if (user_facing_type) {
      if (type.enum_def) {\
        return WrapInNameSpace(*type.enum_def);
      }
*/
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
          // const auto type_name = GenTypeWire(type.VectorType(), "", false);
          const auto type_name = GenType(type.VectorType());
          return "Array<" + type_name + ">";
        }

        case BASE_TYPE_STRUCT:
          return "Never";

        case BASE_TYPE_UNION:
          return "Never";
    }
  }

  // Return a Swift non-scalar type from the table in 
  // std::string GenTypePointer(const Type &type) const {
  //   switch (type.base_type) {
  //     case BASE_TYPE_STRING: {
  //       return "String";
  //     }
  //     case BASE_TYPE_VECTOR: {
  //       const auto type_name = GenTypeWire(type.VectorType(), "", false);
  //       return "Array<" + type_name + ">";
  //     }
  //     case BASE_TYPE_STRUCT: {
  //       return WrapInNameSpace(*type.struct_def);
  //     }
  //     case BASE_TYPE_UNION:
  //     // fall through
  //     default: { return "void"; }
  //   }
  // }

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
};

} // namespace swift

bool GenerateSwift(const Parser &parser, const std::string &path,
                    const std::string &file_name) {
  swift::SwiftGenerator generator(parser, path, file_name);
  return generator.generate();
}


}  // namespace flatbuffers