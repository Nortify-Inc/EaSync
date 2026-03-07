/**
 * @file hybridModel.cpp
 * @author Radmann
 * @brief Implements the complete home assistant model architecture.
 */
#include "../include/hybridModel.hpp"
#include <iostream>
#include <fstream>
#include <sstream>
#include <moe.hpp>

/**
 * @brief Constructor for HybridModel.
 * @param dimModel Model dimension.
 * @param layers Number of layers.
 * @param heads Number of attention heads.
 */
HybridModel::HybridModel(int dimModel, int layers, int heads)
	: transformer(dimModel, layers, heads),
	  moe(dimModel),
	  feedForward(dimModel),
	  attention(heads, true),
	  tokenizer(),
	  memory(nullptr),
	  contextEncoder(nullptr),
	  actionDecoder(),
	  callback(nullptr),
	  dimModel(dimModel),
	  layers(layers),
	  heads(heads)
{
}

/**
 * @brief Generates token sequence from input and context.
 * @param input Input string.
 * @param context Context vector.
 * @return Generated token sequence.
 */
std::vector<int> HybridModel::generate(const std::string& input, const std::vector<std::string>& context)
{
	std::vector<int> tokens = tokenizer.encode(input);
	std::vector<int> ctxTokens;
	if (contextEncoder)
		ctxTokens = contextEncoder->encode(context);
	std::vector<float> transformerOut = transformer.forward(tokens, ctxTokens);
	std::vector<float> moeOut = moe.route(transformerOut);
	std::vector<float> ffOut = feedForward.forward(moeOut);
	std::vector<float> attnOut = attention.multiQuery(ffOut, ffOut, ffOut);
	std::vector<int> outputTokens = actionDecoder.decodeTokens(attnOut);
	if (callback)
		callback("Generated sequence: " + tokenizer.decode(outputTokens));
	return outputTokens;
}

/**
 * @brief Decodes action tokens to string.
 * @param tokens Token sequence.
 * @return Decoded action string.
 */
std::string HybridModel::decodeAction(const std::vector<int>& tokens)
{
	return actionDecoder.decode(tokens);
}

/**
 * @brief Loads model weights from file path.
 * @param path Path to weights file.
 */
void HybridModel::loadWeights(const std::string& path)
{
	transformer.loadWeights(path + "/transformer_weights.bin");
	// MoE does not have loadWeights; remove or replace with correct method if available
	feedForward.initializeWeights(path + "/ff_weights.bin");
	attention.configure(heads, true);
}

/**
 * @brief Planning interface.
 * @param tokens Input token sequence.
 */
void HybridModel::plan(const std::vector<int>& tokens)
{
	std::vector<std::string> context;
	if (contextEncoder) context = contextEncoder->sensorTypes;
	std::string memoryContext;
	if (memory) memoryContext = memory->retrieve("plan");
	std::ostringstream planStream;

	planStream << "Plan: ";
	planStream << "Tokens=";

	for (int t : tokens) planStream << t << ",";
	planStream << " Context=";

	for (const auto& s : context) planStream << s << ",";
	planStream << " MemoryContext=" << memoryContext;

	std::string planResult = planStream.str();

	if (callback) callback(planResult);
}

/**
 * @brief Routing interface.
 * @param tokens Input token sequence.
 */
void HybridModel::route(const std::vector<int>& tokens)
{
	std::vector<int> ctxTokens;
	if (contextEncoder)
		ctxTokens = contextEncoder->encode(contextEncoder->sensorTypes);
	std::vector<float> features = transformer.forward(tokens, ctxTokens);
	std::vector<float> moeOut = moe.route(features);
	
    std::ostringstream routeStream;

	routeStream << "Route: ";
	routeStream << "Tokens=";

	for (int t : tokens) routeStream << t << ",";
	routeStream << " Context=";

	for (const auto& s : contextEncoder ? contextEncoder->sensorTypes : std::vector<std::string>{}) routeStream << s << ",";
	routeStream << " MoEOut=";

	for (float v : moeOut) routeStream << v << ",";

	std::string routeResult = routeStream.str();

	if (callback) callback(routeResult);
}

/**
 * @brief Sets memory module.
 * @param mem Memory module pointer.
 */
void HybridModel::setMemory(Memory* mem)
{
	memory = mem;
}

/**
 * @brief Sets context encoder module.
 * @param encoder Context encoder pointer.
 */
void HybridModel::setContextEncoder(ContextEncoder* encoder)
{
	contextEncoder = encoder;
}

/**
 * @brief Sets callback function.
 * @param cb Callback function pointer.
 */
void HybridModel::setCallback(void (*cb)(const std::string&))
{
	callback = cb;
}

/**
 * @brief Configures model parameters.
 * @param dimModel Model dimension.
 * @param layers Number of layers.
 * @param heads Number of attention heads.
 */
void HybridModel::configure(int dimModel, int layers, int heads)
{
	this->dimModel = dimModel;
	this->layers = layers;
	this->heads = heads;
	transformer.configure(dimModel, layers, heads);
	feedForward.configure(dimModel);
	attention.configure(heads, true);
}
