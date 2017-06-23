//=============================================================================
//
//  mkgig
//
//  create a very basic .gig file with just one sample from CLI
//  inspired by gigedit and https://sourceforge.net/p/linuxsampler/mailman/message/8388136/
//
//  Copyright (C) 2017 Thomas Brand <tom@trellis.ch>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//  https://github.com/7890/mkgig/
//
//=============================================================================

//g++ -o mkgig mkgig.cpp -g `pkg-config --libs --cflags gig`
//tb/1706+

#include <sndfile.h>
#include <gig.h>

SF_INFO sndfile_info;
SNDFILE* sndfile;
gig::Sample *pSample;

int target_bitdepth; //evaluated

char *wave_filename; //argument
char *gig_filename; //argument

const int wave_read_bufsize = 10000; //bytes

void read_snd_meta_data();
void write_sample_data();

using namespace std;

//=============================================================================
int main(int argc, char *argv[])
{
	if(argc<3)
	{
		cerr << "error: need arguments: <wave file (input)> <gig file (output)>" << endl;
		return 1;
	}
	wave_filename=argv[1];
	gig_filename=argv[2];

	try 
	{
		cerr << "reading file metadata" << endl;
		read_snd_meta_data();
		cerr << "creating new gig file" << endl;
		gig::File file;
		file.pInfo->Name = "Single Instrument GIG";

		//create instrument
		gig::Instrument* pInstrument = file.AddInstrument();
		pInstrument->pInfo->Name = "Single Sample Instrument";
	
		DLS::range_t keyRange, velocityRange;
		keyRange.low = 0;
		keyRange.high = 127;
		velocityRange.low = 0;
		velocityRange.high = 63;
	
		//create sample
		pSample = file.AddSample();
		pSample->pInfo->Name = "Anonymous Sample";
	
		//set sample metadata
		pSample->Channels = sndfile_info.channels;
		pSample->BitDepth = target_bitdepth;
		//8: 1 byte = 8 bits
		pSample->FrameSize = target_bitdepth / 8 * sndfile_info.channels;
		pSample->SamplesPerSecond = sndfile_info.samplerate;
		pSample->AverageBytesPerSecond = pSample->FrameSize * pSample->SamplesPerSecond;
		pSample->BlockAlign = pSample->FrameSize;
		pSample->SamplesTotal = sndfile_info.frames;
		//this is important to do before saving /writing sample data
		pSample->Resize(sndfile_info.frames);

		//create region on instrument, add sample to region
		gig::Region* pRegion = pInstrument->AddRegion();
		pRegion->SetSample(pSample);
		pRegion->KeyRange = keyRange;
		pRegion->VelocityRange = velocityRange;
		//pRegion->UnityNote = count;
		pRegion->SampleLoops = 0;
		pRegion->pDimensionRegions[0]->pSample = pSample;

		//before writing sample data, we need to call file.Save()
		cerr << "saving file metadata" << endl;
		file.Save(gig_filename);
		cerr << "saving sample data" << endl;
		write_sample_data();
		cerr << "wrote file '" << gig_filename << "'" << endl;
	}
	catch (RIFF::Exception e)
	{
		e.PrintMessage();
		return 1;
	}
	catch (std::string e)
	{
		cerr << "error: " << e << endl;
		return 1;
	}

	cerr << "done" << endl;
	return 0;
} //main()

//=============================================================================
void read_snd_meta_data()
{
	sndfile_info.format = 0;
	sndfile = sf_open(wave_filename, SFM_READ, &sndfile_info);
	if (!sndfile)
	{
		throw string("could not open file '" + string(wave_filename)+ "'");
	}
	switch (sndfile_info.format & 0xff)
	{
		case SF_FORMAT_PCM_S8:
		case SF_FORMAT_PCM_16:
		case SF_FORMAT_PCM_U8:
			target_bitdepth = 16;
			break;
		case SF_FORMAT_PCM_24:
		case SF_FORMAT_PCM_32:
		case SF_FORMAT_FLOAT:
		case SF_FORMAT_DOUBLE:
			target_bitdepth = 24;
			break;
		default:
			sf_close(sndfile); // close sound file
			throw string("audio format not supported");
	}
} //read_snd_meta_data()

// save samples to .gig file on disk
//=============================================================================
void write_sample_data()
{
	pSample->SetPos(0);

	switch (target_bitdepth)
	{
		case 16:
		{
			short* buffer = new short[wave_read_bufsize * sndfile_info.channels];
			sf_count_t cnt = sndfile_info.frames;
			while (cnt)
			{
				// libsndfile does the conversion for us (if needed)
				int n = sf_readf_short(sndfile, buffer, wave_read_bufsize);
				// write from buffer directly (physically) into .gig file
				pSample->Write(buffer, n);
				cnt -= n;
			}
			delete[] buffer;
			break;
		}
		case 24:
		{
			int* srcbuf = new int[wave_read_bufsize * sndfile_info.channels];
			uint8_t* dstbuf = new uint8_t[wave_read_bufsize * 3 * sndfile_info.channels];
			sf_count_t cnt = sndfile_info.frames;
			while (cnt)
			{
				// libsndfile returns 32 bits, convert to 24
				int n = sf_readf_int(sndfile, srcbuf, wave_read_bufsize);
				int j = 0;
				for (int i = 0 ; i < n * sndfile_info.channels ; i++)
				{
					dstbuf[j++] = srcbuf[i] >> 8;
					dstbuf[j++] = srcbuf[i] >> 16;
					dstbuf[j++] = srcbuf[i] >> 24;
				}
				// write from buffer directly (physically) into .gig file
				pSample->Write(dstbuf, n);
				cnt -= n;
			}
			delete[] srcbuf;
			delete[] dstbuf;
			break;
 		}
	}//end switch target_bitdepth

	// cleanup
	sf_close(sndfile);
} //write_sample_data()

//EOF
