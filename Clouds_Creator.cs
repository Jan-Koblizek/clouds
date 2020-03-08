/*
Copyright (c) 2020 Jan Koblížek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;


public enum QUALITY:int
{
    Low = 64,
    Medium = 128,
    High = 256
}

[ExecuteInEditMode]
public class Clouds_Creator : MonoBehaviour
{
    //quality of the clouds - high, medium, low
    public QUALITY quality = QUALITY.Medium;
    [Range(0.0f, 1.0f)]
    //the amount and thickness of the clouds
    public float coverage = (float)0.4;
    [Range(0.0f, 1.0f)]
    //coverage will change to this value in the incoming clouds
    public float coverageChangeTo = (float)1.0;

    //[Range(0.0f, 1.0f)]
    //public float density = 0.5f;
    //direction of the wind (clouds move in this direction
    public Vector2 windDirection = new Vector2((float)0.0, (float)1.0);
    //speed of the wind (do not use value higher than 20)
    public float windSpeed = (float)4.0;

    //standart Unity procedural sky variables
    public Color atmosphereTint = new Color((float).85, (float).85, (float).85, 1);
    public Color groundColor = new Color((float).369, (float).349, (float).341, 1);
    public Color sunTint = new Color(1, 1, 1, 1);
    public float HDRExposure = (float)1.3;

    //Ambient light for the clouds
    public Color ambientColorTop = new Color(129.0f * (1.5f / 255.0f), 147.0f * (1.5f / 255.0f), 180.0f * (1.5f / 255.0f));
    public Color ambientColorBottom = new Color(110.0f * (1.5f / 255.0f), 112.0f * (1.5f / 255.0f), 117.0f * (1.5f / 255.0f));

    //cloud map the program should use (if generate cloud map is set to true the program generates its own cloud map)
    public Texture cloudMap;
    public bool generateCloudMap = true;

    //position of the clouds (the shift caused by the wind)
    private Vector2 position = new Vector2((float)0.0, (float)0.0);

    //3D noise textures used to generate cloud shapes
    private ComputeShader noiseShader;
    private ComputeShader noiseShaderDetail;
    private RenderTexture noiseTexture_3D;
    private RenderTexture detailNoiseTexture_3D;
    private int noiseGenerator;
    private int detailNoiseGenerator;

    //update texture - generates update values for 1/16 of all pixels
    private RenderTexture skyTextureUpdate;
    //texture of clouds used to overlay the standart Unity procedural sky
    private RenderTexture skyTexture;
    private Material updateTextureMaterial;
    private Material skyTextureMaterial;

    //automaticaly generated dynamic cloud map
    private Material cloudMapMaterial;
    private RenderTexture generatedCloudMap;

    //number of the frame % 16 - tells us which pixels of the skyTexture are updated this frame
    private int frameNumber = 0;
    //time of the last frame
    private float lastUpdateTime;

    private void updateTexture()
    {
        updateTextureMaterial.SetVector("_PositionDirection", new Vector4(position.x, position.y, windDirection.x, windDirection.y));
        updateTextureMaterial.SetFloat("_Speed", windSpeed * (Time.time - lastUpdateTime));
        //Renders the update texture from the updateTextureMaterial
        RenderTexture tepmoraryUpdate = RenderTexture.GetTemporary(skyTextureUpdate.width, skyTextureUpdate.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        Graphics.Blit(skyTextureUpdate, tepmoraryUpdate);
        Graphics.Blit(tepmoraryUpdate, skyTextureUpdate, updateTextureMaterial);
        RenderTexture.ReleaseTemporary(tepmoraryUpdate);

        //Renders the sky texture from skyTextureMaterial (previously rendered texture is used as its update texture)
        RenderTexture temporarySkyTexture = RenderTexture.GetTemporary(skyTexture.width, skyTexture.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        //Copy the previous sky texture into a teporary texture used as the main texture in the skyTextureMaterial
        Graphics.Blit(skyTexture, temporarySkyTexture);
        Graphics.Blit(temporarySkyTexture, skyTexture, skyTextureMaterial);
        RenderTexture.ReleaseTemporary(temporarySkyTexture);

        //Increase the FrameNumber by 1 - so we do not update the same 1/16 of the pixels each frame.
        frameNumber = (frameNumber + 1) % 16;
        updateTextureMaterial.SetInt("_FrameNumber", frameNumber);
        skyTextureMaterial.SetInt("_FrameNumber", frameNumber);
    }

    private void cloudMapGenerate(int first)
    {
        //initial coverage value - used in the first frame
        cloudMapMaterial.SetFloat("_Coverage", coverage);
        //variable tells shader if this is the first frame (initial coverage value should be used)
        cloudMapMaterial.SetInt("_First", first);
        //coverage the sky should change to
        cloudMapMaterial.SetFloat("_CoverageChangeTo", coverageChangeTo);
        //position of the clouds compared to the initial state and the wind direction
        cloudMapMaterial.SetVector("_PositionDirection", new Vector4(position.x, position.y, windDirection.x, windDirection.y));
        //speed of the wind
        cloudMapMaterial.SetFloat("_Speed", windSpeed);
        //time since the last frame
        cloudMapMaterial.SetFloat("_DeltaTime", (Time.time - lastUpdateTime));
        //Temporary copy of the cloud map is used as an input for the cloudMapMaterial.
        RenderTexture tempCloudMap = RenderTexture.GetTemporary(generatedCloudMap.width, generatedCloudMap.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        Graphics.Blit(generatedCloudMap, tempCloudMap);
        Graphics.Blit(tempCloudMap, generatedCloudMap, cloudMapMaterial);
        RenderTexture.ReleaseTemporary(tempCloudMap);
    }
    
    //Was used for testing purposes - updates quality and coverage directly from the game.
    internal void ChangeSettings(int qual, float cover)
    {
        switch (qual)
        {
            case 0:
                quality = QUALITY.Low;
                break;
            case 1:
                quality = QUALITY.Medium;
                break;
            case 2:
                quality = QUALITY.High;
                break;
        }
        coverage = cover;
        this.Start();
    }

    //Was used for testing purposes - updates coverage directly from the game.
    internal void ChangeCoverage(float cover)
    {
        coverage = cover;
        cloudMapMaterial.SetFloat("_Coverage", coverage);
    }
    /*
    Start() initializes all necessary variables and textures.
    
    -Loads all necessary shaders and materials from the Resources folder
    -Sets up initial values of the shader properties
    -Generates 3D noises used for basic cloud shapes
    -Generates the initial cloud map of specified coverage
    -Updates the skyTexture 16 times with the updateTexture (so the sky is allready generated in the first frame)
    */
    void Start()
    {
        /*
        Loads necessary materials and shaders from Resources folder
        */
        position = new Vector2((float)0.0, (float)0.0);
        lastUpdateTime = Time.time;
        noiseShader = (UnityEngine.ComputeShader)Resources.Load("Clouds/Noise_Shader");
        noiseShaderDetail = (UnityEngine.ComputeShader)Resources.Load("Clouds/Small_Details_Shader");
        cloudMapMaterial = (UnityEngine.Material)Resources.Load("Clouds/CloudMapMaterial");
        updateTextureMaterial = (UnityEngine.Material)Resources.Load("Clouds/CloudUpdate");
        skyTextureMaterial = (UnityEngine.Material)Resources.Load("Clouds/CloudTexture");
        RenderSettings.skybox = (UnityEngine.Material)Resources.Load("Clouds/Skybox-Image");

        /*
        Sets up basic variables for the sky rendering
        */
        updateTextureMaterial.SetColor("_SunTint", sunTint);
        updateTextureMaterial.SetFloat("_HdrExposure", HDRExposure);
        updateTextureMaterial.SetColor("_Clouds_Ambient_Bottom", ambientColorBottom);
        updateTextureMaterial.SetColor("_Clouds_Ambient_Top", ambientColorTop);
        updateTextureMaterial.SetFloat("_Density", 0.04f);
        RenderSettings.skybox.SetColor("_SunTint", sunTint);
        RenderSettings.skybox.SetFloat("_HdrExposure", HDRExposure);
        RenderSettings.skybox.SetColor("_Color", atmosphereTint);
        RenderSettings.skybox.SetColor("_GroundColor", groundColor);

        /*
        Big detail 3D texture - Layered Voronoi noise at different frequencies. Generated from a compute shader.
        The results are saved to noiseTexture_3D
        */
        noiseTexture_3D = new RenderTexture(128, 128, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        noiseTexture_3D.enableRandomWrite = true;
        noiseTexture_3D.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        noiseTexture_3D.volumeDepth = 128;
        noiseTexture_3D.Create();
        noiseGenerator = noiseShader.FindKernel("CSMain");
        noiseShader.SetTexture(noiseGenerator, "Result", noiseTexture_3D);
        float t = Time.time / 1000 + 10;
        noiseShader.SetFloat("Time", t);
        noiseShader.Dispatch(noiseGenerator, 128 / 8, 128 / 8, 128 / 8);
        updateTextureMaterial.SetTexture("_3dTexture", noiseTexture_3D);

        /*
        Small detail shader (used to add cloud details). The results are saved to detailNoiseTexture_3D
        */ 
        detailNoiseTexture_3D = new RenderTexture(64, 64, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        detailNoiseTexture_3D.enableRandomWrite = true;
        detailNoiseTexture_3D.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        detailNoiseTexture_3D.volumeDepth = 64;
        detailNoiseTexture_3D.Create();
        detailNoiseGenerator = noiseShaderDetail.FindKernel("CSMain");
        noiseShaderDetail.SetTexture(detailNoiseGenerator, "Result", detailNoiseTexture_3D);
        noiseShaderDetail.SetFloat("Time", t);
        noiseShaderDetail.Dispatch(detailNoiseGenerator, 64 / 8, 64 / 8, 64 / 8);
        updateTextureMaterial.SetTexture("_3dTexture_Distort", detailNoiseTexture_3D);

        /*
        Cloud Map - 2D texture tells us the cloud density at different parts of the sky
        */
        if (generateCloudMap)
        {
            generatedCloudMap = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
            generatedCloudMap.enableRandomWrite = true;
            generatedCloudMap.Create();
            cloudMapGenerate(1);
            
            //Setting cloud map for the cloud update shader.
            updateTextureMaterial.SetTexture("_Cloud_Map", generatedCloudMap);
        }
        else
        {
            updateTextureMaterial.SetTexture("_Cloud_Map", cloudMap);
        }

        /*
        Update shader - calculates values at 1/16 of the skyTexture pixels.
        It is 4 times smaller than the skyTexture.
        */
        skyTextureUpdate = new RenderTexture((int)quality, (int)quality / 2, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        skyTextureUpdate.enableRandomWrite = true;
        skyTextureMaterial.SetTexture("_UpdateTex", skyTextureUpdate);
        skyTextureUpdate.Create();

        /*
        The main cloud texture - updates 1/16 of its pixels from the Update texture
        */
        skyTexture = new RenderTexture(4*(int)quality, 4*(int)quality / 2, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        skyTexture.enableRandomWrite = true;
        RenderSettings.skybox.SetTexture("_Texture", skyTexture);
        skyTexture.Create();

        //Pass initial frame number -1 to updateTextureMaterial and skyTextureMaterial
        updateTextureMaterial.SetInt("_FrameNumber", 0);
        skyTextureMaterial.SetInt("_FrameNumber", 0);

        /*
        Calls Update Shader 16 times. This updates all the pixels in the skyTexture.
        */
        for (int i = 0; i < 16; i++)
        {
            updateTexture();
        }
    }

    void Update()
    {
        /*
         If settings change in the Unity inspector call the Start() function again and initialize all the necessary materials, shaders and textures there.
         */
        if (!Application.isPlaying)
        {
            noiseTexture_3D.Release();
            detailNoiseTexture_3D.Release();
            generatedCloudMap.Release();
            skyTextureUpdate.Release();
            skyTexture.Release();
            this.Start();
        }
        else
        {
            /*
            Generate update texture from the updateTextureMaterial
            */
            updateTexture();
            

            //Generates a cloud map for the next frame
            if (generateCloudMap)
            {
                cloudMapGenerate(0);
            }
            position = position + windDirection * windSpeed * (Time.time - lastUpdateTime);
            lastUpdateTime = Time.time;
        }

    }

   /*
    void OnGUI()
    {

        GUI.DrawTexture(new Rect(0, 0, 512, 512), generatedCloudMap, ScaleMode.StretchToFill, false);
    }
    */
    



}
