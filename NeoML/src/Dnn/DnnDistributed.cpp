/* Copyright © 2017-2020 ABBYY Production LLC
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

#include <common.h>
#pragma hdrstop

#include <thread>
#include <vector>
#include <functional>
#include <NeoMathEngine/NeoMathEngine.h>
#include <NeoML/Dnn/DnnDistributed.h>

namespace NeoML {

void CDistributedTraining::initialize( CArchive& archive, int count )
{
    for( int i = 0; i < count; i++ ){
        rands.Add( new CRandom( 42 ) );
        cnns.Add( new CDnn( *rands[i], *mathEngines[i] ) );
        cnns[i]->SetInitializer( new CDnnDistributedInitializer( *rands[i], mathEngines[i], cnns[i]->GetInitializer() ) );
        archive.Serialize( *cnns[i] );
        archive.Seek( 0, static_cast<CBaseFile::TSeekPosition>( 0 ) );
    }
}

CDistributedTraining::CDistributedTraining( CArchive& archive, int count )
{
    mathEngines.SetSize( count );
    CreateDistributedCpuMathEngines( mathEngines.GetPtr(), count );
    initialize( archive, count );
}

CDistributedTraining::CDistributedTraining( CArchive& archive, const CArray<int>& cudaDevs )
{
    mathEngines.SetSize( cudaDevs.Size() );
    CreateDistributedCudaMathEngines( mathEngines.GetPtr(), cudaDevs.Size(), cudaDevs.GetPtr() );
    initialize( archive, cudaDevs.Size() );
}

CDistributedTraining::~CDistributedTraining()
{
    for( int i = 0; i < cnns.Size(); i++ ){
        delete cnns[i];
        delete rands[i];
        delete mathEngines[i];
    }
}

void CDistributedTraining::RunAndLearnOnce( IDistributedDataset& data )
{
    std::vector<std::thread> threads;
    for ( int i = 0; i < cnns.Size(); i++ ) {
        std::thread t( std::bind(
            [&]( int thread ){
                data.SetInputBatch( *cnns[thread], thread );
                cnns[thread]->RunAndLearnOnce();
            },  i ) );
        threads.push_back( std::move( t ) );
    }
    for ( int i = 0; i < cnns.Size(); i++ ) {
        threads[i].join();
    }
}

void CDistributedTraining::GetLastLoss( const CString& layerName, CArray<float>& losses )
{
    losses.SetSize( cnns.Size() );
    for( int i = 0; i < cnns.Size(); i++ ){
        CLossLayer* lossLayer = dynamic_cast<CLossLayer*>( cnns[i]->GetLayer( layerName ).Ptr() );
        if( lossLayer == nullptr ){
            losses[i] = dynamic_cast<CCtcLossLayer*>( cnns[i]->GetLayer( layerName ).Ptr() )->GetLastLoss();
        } else {
            losses[i] = lossLayer->GetLastLoss();
        }
    }
}

} // namespace NeoML