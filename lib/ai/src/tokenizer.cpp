/*
 * Tokenizer.cpp
 * ─────────────
 * Tokenizer BPE Qwen2. Lê tokenizer.json (HuggingFace format).
 * vocab: {"token": id_number, ...}
 * merges: ["tok1 tok2", ...]
 */

#include "tokenizer.hpp"

#include <algorithm>
#include <climits>
#include <fstream>
#include <regex>
#include <sstream>
#include <stdexcept>

// ─────────────────────────────────────────────────────────────────────────────
//  Parser JSON mínimo mas correto para o formato do tokenizer.json
// ─────────────────────────────────────────────────────────────────────────────
namespace {

// Lê uma string JSON a partir de pos (que deve apontar para o '"' inicial).
// Avança pos para após o '"' de fechamento. Retorna a string decodificada.
static std::string read_json_string(const std::string& s, size_t& pos)
{
    if (pos >= s.size() || s[pos] != '"')
        throw std::runtime_error("expected '\"'");
    ++pos; // pula '"' inicial
    std::string val;
    val.reserve(32);
    while (pos < s.size()) {
        char c = s[pos++];
        if (c == '"') return val;
        if (c == '\\' && pos < s.size()) {
            char e = s[pos++];
            switch (e) {
                case '"':  val += '"';  break;
                case '\\': val += '\\'; break;
                case '/':  val += '/';  break;
                case 'n':  val += '\n'; break;
                case 'r':  val += '\r'; break;
                case 't':  val += '\t'; break;
                case 'b':  val += '\b'; break;
                case 'f':  val += '\f'; break;
                case 'u': {
                    // \uXXXX — decodifica codepoint básico
                    if (pos + 4 > s.size()) { val += '?'; break; }
                    std::string hex = s.substr(pos, 4);
                    pos += 4;
                    unsigned cp = std::stoul(hex, nullptr, 16);
                    // Encode UTF-8
                    if (cp < 0x80) {
                        val += static_cast<char>(cp);
                    } else if (cp < 0x800) {
                        val += static_cast<char>(0xC0 | (cp >> 6));
                        val += static_cast<char>(0x80 | (cp & 0x3F));
                    } else {
                        val += static_cast<char>(0xE0 | (cp >> 12));
                        val += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        val += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                    break;
                }
                default: val += e; break;
            }
        } else {
            val += c;
        }
    }
    throw std::runtime_error("unterminated string");
}

// Pula whitespace
static void skip_ws(const std::string& s, size_t& pos)
{
    while (pos < s.size() && (s[pos] == ' ' || s[pos] == '\t' ||
                               s[pos] == '\n' || s[pos] == '\r'))
        ++pos;
}

// Lê um número inteiro (int64)
static int64_t read_int(const std::string& s, size_t& pos)
{
    bool neg = false;
    if (pos < s.size() && s[pos] == '-') { neg = true; ++pos; }
    int64_t val = 0;
    if (pos >= s.size() || !std::isdigit((unsigned char)s[pos]))
        throw std::runtime_error("expected digit");
    while (pos < s.size() && std::isdigit((unsigned char)s[pos]))
        val = val * 10 + (s[pos++] - '0');
    // skip fractional / exponent if present (shouldn't be in vocab ids)
    if (pos < s.size() && (s[pos] == '.' || s[pos] == 'e' || s[pos] == 'E')) {
        while (pos < s.size() && s[pos] != ',' && s[pos] != '}' && s[pos] != ']')
            ++pos;
    }
    return neg ? -val : val;
}

// Pula qualquer valor JSON (objeto, array, string, number, bool, null)
static void skip_value(const std::string& s, size_t& pos);

static void skip_object(const std::string& s, size_t& pos)
{
    if (pos >= s.size() || s[pos] != '{') return;
    ++pos;
    skip_ws(s, pos);
    if (pos < s.size() && s[pos] == '}') { ++pos; return; }
    while (pos < s.size()) {
        skip_ws(s, pos);
        if (s[pos] == '"') read_json_string(s, pos);
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ':') ++pos;
        skip_ws(s, pos);
        skip_value(s, pos);
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ',') { ++pos; continue; }
        if (pos < s.size() && s[pos] == '}') { ++pos; return; }
    }
}

static void skip_array(const std::string& s, size_t& pos)
{
    if (pos >= s.size() || s[pos] != '[') return;
    ++pos;
    skip_ws(s, pos);
    if (pos < s.size() && s[pos] == ']') { ++pos; return; }
    while (pos < s.size()) {
        skip_ws(s, pos);
        skip_value(s, pos);
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ',') { ++pos; continue; }
        if (pos < s.size() && s[pos] == ']') { ++pos; return; }
    }
}

static void skip_value(const std::string& s, size_t& pos)
{
    skip_ws(s, pos);
    if (pos >= s.size()) return;
    char c = s[pos];
    if (c == '{')       skip_object(s, pos);
    else if (c == '[')  skip_array(s, pos);
    else if (c == '"')  read_json_string(s, pos);
    else if (c == 't')  { pos += 4; } // true
    else if (c == 'f')  { pos += 5; } // false
    else if (c == 'n')  { pos += 4; } // null
    else                read_int(s, pos);
}

// Navega até o objeto de uma chave específica (busca superficial)
// Retorna pos logo após o '{' do objeto alvo, ou string::npos se não encontrar.
static size_t find_object_start(const std::string& s, size_t from,
                                 const std::string& key)
{
    const std::string needle = "\"" + key + "\"";
    size_t pos = s.find(needle, from);
    while (pos != std::string::npos) {
        size_t after = pos + needle.size();
        skip_ws(s, after);
        if (after < s.size() && s[after] == ':') {
            ++after;
            skip_ws(s, after);
            if (after < s.size() && s[after] == '{')
                return after;
        }
        pos = s.find(needle, pos + 1);
    }
    return std::string::npos;
}

static size_t find_array_start(const std::string& s, size_t from,
                                const std::string& key)
{
    const std::string needle = "\"" + key + "\"";
    size_t pos = s.find(needle, from);
    while (pos != std::string::npos) {
        size_t after = pos + needle.size();
        skip_ws(s, after);
        if (after < s.size() && s[after] == ':') {
            ++after;
            skip_ws(s, after);
            if (after < s.size() && s[after] == '[')
                return after;
        }
        pos = s.find(needle, pos + 1);
    }
    return std::string::npos;
}

// Lê vocab: {"token": id, ...}
static void parse_vocab(const std::string& s, size_t pos,
                         std::unordered_map<std::string, int64_t>& str_to_id,
                         std::unordered_map<int64_t, std::string>& id_to_str)
{
    if (pos >= s.size() || s[pos] != '{')
        throw std::runtime_error("vocab: expected '{'");
    ++pos;
    skip_ws(s, pos);
    if (pos < s.size() && s[pos] == '}') return;

    while (pos < s.size()) {
        skip_ws(s, pos);
        if (s[pos] == '}') break;

        // key (token string)
        std::string tok = read_json_string(s, pos);
        skip_ws(s, pos);
        if (pos >= s.size() || s[pos] != ':')
            throw std::runtime_error("vocab: expected ':'");
        ++pos;
        skip_ws(s, pos);

        // value (integer id)
        int64_t id = read_int(s, pos);
        str_to_id[tok] = id;
        id_to_str[id]  = tok;

        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ',') { ++pos; continue; }
        if (pos < s.size() && s[pos] == '}') { ++pos; break; }
    }
}

// Lê merges: ["tok1 tok2", ...]
static void parse_merges(const std::string& s, size_t pos,
                          std::unordered_map<std::string, int>& merge_rank)
{
    if (pos >= s.size() || s[pos] != '[')
        throw std::runtime_error("merges: expected '['");
    ++pos;
    skip_ws(s, pos);
    if (pos < s.size() && s[pos] == ']') return;

    int rank = 0;
    while (pos < s.size()) {
        skip_ws(s, pos);
        if (s[pos] == ']') break;
        if (s[pos] == '"') {
            std::string merge = read_json_string(s, pos);
            merge_rank[merge] = rank++;
        } else {
            skip_value(s, pos);
        }
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ',') { ++pos; continue; }
        if (pos < s.size() && s[pos] == ']') { ++pos; break; }
    }
}

} // anonymous namespace

// ─────────────────────────────────────────────────────────────────────────────
//  Byte encoder/decoder (GPT-2 style)
// ─────────────────────────────────────────────────────────────────────────────
void Tokenizer::build_byte_encoder()
{
    std::vector<int> bs;
    for (int c = '!'; c <= '~'; ++c)    bs.push_back(c);
    for (int c = 0xA1; c <= 0xAC; ++c)  bs.push_back(c);
    for (int c = 0xAE; c <= 0xFF; ++c)  bs.push_back(c);

    std::vector<int> cs = bs;
    int n = 0;
    for (int b = 0; b < 256; ++b) {
        if (std::find(bs.begin(), bs.end(), b) == bs.end()) {
            bs.push_back(b);
            cs.push_back(256 + n++);
        }
    }

    for (size_t i = 0; i < bs.size(); ++i) {
        std::string utf8;
        int cp = cs[i];
        if (cp < 0x80) {
            utf8 += static_cast<char>(cp);
        } else if (cp < 0x800) {
            utf8 += static_cast<char>(0xC0 | (cp >> 6));
            utf8 += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            utf8 += static_cast<char>(0xE0 | (cp >> 12));
            utf8 += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            utf8 += static_cast<char>(0x80 | (cp & 0x3F));
        }
        byte_encoder_[static_cast<uint8_t>(bs[i])] = utf8;
        byte_decoder_[utf8] = static_cast<uint8_t>(bs[i]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Construtor
// ─────────────────────────────────────────────────────────────────────────────
Tokenizer::Tokenizer(const std::string& tokenizer_json_path)
{
    build_byte_encoder();

    std::ifstream f(tokenizer_json_path, std::ios::binary);
    if (!f.is_open())
        throw std::runtime_error("Tokenizer: não foi possível abrir " + tokenizer_json_path);

    std::ostringstream ss;
    ss << f.rdbuf();
    const std::string json = ss.str();
    fprintf(stderr, "[Tokenizer] Arquivo lido: %zu bytes\n", json.size());

    // Encontra o objeto "model"
    size_t model_pos = find_object_start(json, 0, "model");
    if (model_pos == std::string::npos)
        throw std::runtime_error("Tokenizer: campo 'model' não encontrado");

    // Dentro do model, encontra "vocab"
    size_t vocab_pos = find_object_start(json, model_pos, "vocab");
    if (vocab_pos == std::string::npos)
        throw std::runtime_error("Tokenizer: campo 'vocab' não encontrado");

    fprintf(stderr, "[Tokenizer] Parseando vocab...\n");
    parse_vocab(json, vocab_pos, str_to_id_, id_to_str_);
    fprintf(stderr, "[Tokenizer] vocab: %zu tokens\n", str_to_id_.size());

    if (str_to_id_.empty())
        throw std::runtime_error("Tokenizer: vocab vazio após carregamento");

    // Dentro do model, encontra "merges"
    size_t merges_pos = find_array_start(json, model_pos, "merges");
    if (merges_pos != std::string::npos) {
        fprintf(stderr, "[Tokenizer] Parseando merges...\n");
        parse_merges(json, merges_pos, merge_rank_);
        fprintf(stderr, "[Tokenizer] merges: %zu\n", merge_rank_.size());
    }

    // Tokens especiais do added_tokens
    size_t added_pos = find_array_start(json, 0, "added_tokens");
    if (added_pos != std::string::npos) {
        size_t pos = added_pos + 1; // pula '['
        skip_ws(json, pos);
        while (pos < json.size() && json[pos] != ']') {
            skip_ws(json, pos);
            if (json[pos] == '{') {
                // lê objeto: procura "id" e "content"
                size_t obj_start = pos;
                ++pos;
                std::string content;
                int64_t id = -1;
                skip_ws(json, pos);
                while (pos < json.size() && json[pos] != '}') {
                    skip_ws(json, pos);
                    if (json[pos] != '"') { ++pos; continue; }
                    std::string k = read_json_string(json, pos);
                    skip_ws(json, pos);
                    if (json[pos] == ':') ++pos;
                    skip_ws(json, pos);
                    if (k == "id") {
                        id = read_int(json, pos);
                    } else if (k == "content") {
                        content = read_json_string(json, pos);
                    } else {
                        skip_value(json, pos);
                    }
                    skip_ws(json, pos);
                    if (json[pos] == ',') ++pos;
                }
                if (json[pos] == '}') ++pos;
                if (!content.empty() && id >= 0) {
                    str_to_id_[content] = id;
                    id_to_str_[id]      = content;
                }
            } else {
                skip_value(json, pos);
            }
            skip_ws(json, pos);
            if (pos < json.size() && json[pos] == ',') ++pos;
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BPE
// ─────────────────────────────────────────────────────────────────────────────
std::vector<std::string> Tokenizer::bpe(const std::string& word) const
{
    std::vector<std::string> symbols;
    for (unsigned char c : word) {
        auto it = byte_encoder_.find(c);
        symbols.push_back(it != byte_encoder_.end()
                          ? it->second
                          : std::string(1, static_cast<char>(c)));
    }

    while (symbols.size() > 1) {
        int best_rank = INT_MAX;
        size_t best_i = 0;
        bool found = false;

        for (size_t i = 0; i + 1 < symbols.size(); ++i) {
            auto it = merge_rank_.find(symbols[i] + " " + symbols[i + 1]);
            if (it != merge_rank_.end() && it->second < best_rank) {
                best_rank = it->second;
                best_i    = i;
                found     = true;
            }
        }
        if (!found) break;

        symbols[best_i] += symbols[best_i + 1];
        symbols.erase(symbols.begin() + static_cast<std::ptrdiff_t>(best_i + 1));
    }

    return symbols;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pré-tokenização
// ─────────────────────────────────────────────────────────────────────────────
std::vector<std::string> Tokenizer::pretokenize(const std::string& text) const
{
    static const std::regex pat(
        R"('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^\s[:alpha:][:digit:]]+|\s+(?!\S)|\s+)",
        std::regex::optimize);

    std::vector<std::string> tokens;
    auto it  = std::sregex_iterator(text.begin(), text.end(), pat);
    auto end = std::sregex_iterator();
    for (; it != end; ++it)
        tokens.push_back(it->str());
    return tokens;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Encode
// ─────────────────────────────────────────────────────────────────────────────
std::vector<int64_t> Tokenizer::encode_word(const std::string& word) const
{
    std::vector<int64_t> ids;
    for (const auto& p : bpe(word)) {
        auto it = str_to_id_.find(p);
        if (it != str_to_id_.end())
            ids.push_back(it->second);
    }
    return ids;
}

std::vector<int64_t> Tokenizer::encode(const std::string& text) const
{
    std::vector<int64_t> ids;
    for (const auto& word : pretokenize(text)) {
        auto w = encode_word(word);
        ids.insert(ids.end(), w.begin(), w.end());
    }
    return ids;
}

void Tokenizer::push_special(std::vector<int64_t>& ids, const std::string& tok) const
{
    auto it = str_to_id_.find(tok);
    if (it != str_to_id_.end())
        ids.push_back(it->second);
}

std::vector<int64_t> Tokenizer::encode_chat(
    const std::string& user_message,
    const std::string& system_prompt) const
{
    std::vector<int64_t> ids;
    ids.reserve(512);

    auto push = [&](const std::string& t) {
        auto w = encode(t);
        ids.insert(ids.end(), w.begin(), w.end());
    };

    push_special(ids, "<|im_start|>");
    push("system\n");
    push(system_prompt);
    push_special(ids, "<|im_end|>");
    push("\n");

    push_special(ids, "<|im_start|>");
    push("user\n");
    push(user_message);
    push_special(ids, "<|im_end|>");
    push("\n");

    push_special(ids, "<|im_start|>");
    push("assistant\n");

    return ids;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Decode
// ─────────────────────────────────────────────────────────────────────────────
std::string Tokenizer::id_to_token(int64_t id) const
{
    auto it = id_to_str_.find(id);
    return it != id_to_str_.end() ? it->second : "";
}

std::string Tokenizer::decode(const std::vector<int64_t>& ids) const
{
    std::string raw;
    for (int64_t id : ids) {
        if (id >= 151643) continue; // pula tokens especiais
        auto it = id_to_str_.find(id);
        if (it != id_to_str_.end())
            raw += it->second;
    }

    // Decodifica byte-level encoding
    std::string result;
    result.reserve(raw.size());
    size_t i = 0;
    while (i < raw.size()) {
        bool found = false;
        for (int len : {3, 2, 1}) {
            if (i + static_cast<size_t>(len) > raw.size()) continue;
            auto it = byte_decoder_.find(raw.substr(i, len));
            if (it != byte_decoder_.end()) {
                result += static_cast<char>(it->second);
                i += len;
                found = true;
                break;
            }
        }
        if (!found) result += raw[i++];
    }

    return result;
}