/* Copyright © 2017-2023 ABBYY

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--------------------------------------------------------------------------------------------------------------*/

#pragma once

#include <GradientBoostFastHistProblem.h>
#include <GradientBoostStatisticsSingle.h>
#include <GradientBoostStatisticsMulti.h>
#include <NeoML/TraditionalML/Model.h>

namespace NeoML {

class IThreadPool;
class CRegressionTree;
class CLinkedRegressionTree;

// Tree building parameters
struct CGradientBoostFastHistTreeBuilderParams final {
	float L1RegFactor{}; // the L1 regularization factor
	float L2RegFactor{}; // the L2 regularization factor
	float MinSubsetHessian{}; // the minimum hessian value for a subtree
	int ThreadCount{}; // the number of processing threads to be used
	int MaxTreeDepth{}; // the maximum tree depth
	float PruneCriterionValue{}; // the value of criterion difference when the nodes should be merged (set to 0 to never merge)
	int MaxNodesCount{}; // the maximum number of nodes in a tree (set to NotFound == -1 for no limitation)
	int MaxBins{}; // the maximum histogram size for a feature
	float MinSubsetWeight{}; // the minimum subtree weight
	float DenseTreeBoostCoefficient{}; // the dense tree boost coefficient

	CGradientBoostFastHistTreeBuilderParams() = default;
	CGradientBoostFastHistTreeBuilderParams( const CGradientBoostFastHistTreeBuilderParams& ) = default;
	CGradientBoostFastHistTreeBuilderParams( const CGradientBoostFastHistTreeBuilderParams& params, int realThreadsCount ) :
		CGradientBoostFastHistTreeBuilderParams( params )
	{ ThreadCount = realThreadsCount; }
};

// Tree builder
template<class T>
class CGradientBoostFastHistTreeBuilder : public virtual IObject {
public:
	CGradientBoostFastHistTreeBuilder( const CGradientBoostFastHistTreeBuilderParams& params, CTextStream* logStream, int predictionSize );

	// Builds a tree
	CPtr<CRegressionTree> Build( const CGradientBoostFastHistProblem& problem,
		const CArray<typename T::Type>& gradients, const CArray<typename T::Type>& hessians, const CArray<double>& weights );

	// A node in the tree
	struct CNode final {
		int Level; // the level of the node in the final tree
		int VectorSetPtr; // a pointer to the start of the vector set of the node
		int VectorSetSize; // the size of the vector set of the node
		int HistPtr = NotFound; // a pointer to the histogram created on the vectors of the node
		T Statistics{}; // statistics of the vectors of the node
		int SplitFeatureId = NotFound; // the identifier of the feature used to split this node
		int Left = NotFound; // the pointer to the left child
		int Right = NotFound; // the pointer to the right child
		T LeftStatistics{}; // saved statistics for the left child
		T RightStatistics{}; // saved statistics for the right child

		CNode( int level, int vectorSetPtr, int vectorSetSize ) :
			Level( level ),
			VectorSetPtr( vectorSetPtr ),
			VectorSetSize( vectorSetSize )
		{}
	};

	struct CThreadsBuffers final {
		CArray<double> SplitGainsBuffer{};
		CArray<int> SplitIdsBuffer{};
		CArray<T> LeftCandidates{};
		CArray<T> RightCandidates{};
	};

protected:
	~CGradientBoostFastHistTreeBuilder() override; // delete prohibited

private:
	IThreadPool* const threadPool; // parallel executors
	const CGradientBoostFastHistTreeBuilderParams params; // classifier parameters
	CTextStream* const logStream; // the logging stream

	int predictionSize{}; // size of prediction value in leaves
	int histSize{}; // histogram size
	CArray<CNode> nodes{}; // the final tree nodes
	CArray<int> nodeStack{}; // the stack used to build the tree using depth-first search
	CArray<int> vectorSet{}; // the array that stores the vector sets for the nodes
	CArray<int> freeHists{}; // free histograms list
	CArray<T> histStats{}; // the array for storing histograms
	CArray<int> idPos{}; // the identifier positions in the current histogram

	// Caching threads temporary memory
	CArray<T> tempHistStats{}; // a temporary array for building histograms
	mutable CThreadsBuffers tb{};

	void initVectorSet( int size );
	void initHistData( const CGradientBoostFastHistProblem& problem );
	int allocHist();
	// Free the unnecessary histogram
	// A histogram is identified by the pointer to its start in the histData array
	void freeHist( int ptr ) { freeHists.Add( ptr ); }
	void subHist( int firstPtr, int secondPtr );
	void buildHist( const CGradientBoostFastHistProblem& problem, const CNode& node,
		const CArray<typename T::Type>& gradients, const CArray<typename T::Type>& hessians, const CArray<double>& weights,
		T& totalStats );
	int evaluateSplit( const CGradientBoostFastHistProblem& problem, CNode& node ) const;
	void applySplit( const CGradientBoostFastHistProblem& problem, int node, int& leftNode, int& rightNode );
	bool prune( int node );
	CPtr<CLinkedRegressionTree> buildTree( int node, const CArray<int>& featureIndexes, const CArray<float>& cuts ) const;
};

} // namespace NeoML
