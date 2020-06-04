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
    High = 256,
    Ultra = 512
}

[System.Serializable]
public class WindDirection
{
    public float X = 1.0f;
    public float Z = 0.0f;
}

[ExecuteInEditMode]
public class Clouds_Creator : MonoBehaviour
{
    //Camera, that represents the player view
    public Camera characterCamera;
    //quality of the clouds - high, medium, low
    public QUALITY quality = QUALITY.Medium;

    public Texture2D cloudMap;
    public bool generateCloudMap = true;
    [ConditionalProperty("generateCloudMap")]
    public float cumulusAppearanceProbability = 0.3f;
    [ConditionalProperty("generateCloudMap")]
    public float stratusAppearanceProbability = 0.3f;
    [ConditionalProperty("generateCloudMap")]
    public float stratocumulusAppearanceProbability = 0.3f;

    [Range(0.0f, 1.0f)]
    //the amount and thickness of the clouds
    public float coverage = (float)0.4;
    [Range(0.0f, 1.0f)]
    //coverage will change to this value in the incoming clouds
    public float coverageChangeTo = (float)1.0;

    //direction of the wind (clouds move in this direction
    public WindDirection windDirection;
    //speed of the wind (do not use value higher than 20)
    public float windSpeed = (float)4.0;

    //standart Unity procedural sky variables
    public Color atmosphereTint = new Color((float).65, (float).65, (float).65, 1);
    public Color groundColor = new Color((float).369, (float).349, (float).341, 1);
    public Color sunTint = new Color(1, 1, 1, 1);
    public float HDRExposure = (float)1.3;

    //Ambient light for the clouds
    public Color ambientColorTop = new Color(129.0f * (1.5f / 255.0f), 147.0f * (1.5f / 255.0f), 180.0f * (1.5f / 255.0f));
    public Color ambientColorBottom = new Color(110.0f * (1.5f / 255.0f), 112.0f * (1.5f / 255.0f), 117.0f * (1.5f / 255.0f));

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
    //texture of clouds used to overlay the standard Unity procedural sky
    private RenderTexture skyTexture;
    private RenderTexture skyTexture2;
    private bool useSecondTexture;
    private Material updateTextureMaterial;
    private Material skyTextureMaterial;

    //automaticaly generated dynamic cloud map
    private Material cloudMapMaterial;
    private RenderTexture generatedCloudMap;


    private Material shadowMaterial;
    private MeshRenderer shadowPlane;

    private RenderTexture test;

    //number of the frame % 16 - tells us which pixels of the skyTexture are updated this frame
    private int frameNumber = 0;
    //time of the last frame
    private float lastUpdateTime;

    private Vector3 previousPosition;

    float deltaTime = 0.0f;

    //Updates the cloud texture
    private void updateTexture(bool first)
    {
        Vector3 cameraShift = characterCamera.transform.position - previousPosition;
        previousPosition = characterCamera.transform.position;
        Vector2 shift;
        //Do use no shift the first frame
        if (first)
        {
            shift = new Vector2(0,0);
        }
        else
        {
            shift = new Vector2(-cameraShift.x + windDirection.X * windSpeed * (Time.time - lastUpdateTime),
                -cameraShift.z + windDirection.Z * windSpeed * (Time.time - lastUpdateTime));
        }
        
        updateTextureMaterial.SetVector("_PositionDirection", new Vector4(position.x, position.y, -windDirection.X, -windDirection.Z));
        updateTextureMaterial.SetFloat("_Speed", windSpeed * (Time.time - lastUpdateTime));
        //Renders the update texture from the updateTextureMaterial
        RenderTexture tepmoraryUpdate = RenderTexture.GetTemporary(skyTextureUpdate.width, skyTextureUpdate.height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        Graphics.Blit(skyTextureUpdate, tepmoraryUpdate);
        Graphics.Blit(tepmoraryUpdate, skyTextureUpdate, updateTextureMaterial);
        RenderTexture.ReleaseTemporary(tepmoraryUpdate);

        skyTextureMaterial.SetVector("_Shift", new Vector4(-shift.x, -shift.y, 0.0f, 0.0f));

        if (first)
        {
            skyTextureMaterial.SetInt("_First", 1);
        }
        else
        {
            skyTextureMaterial.SetInt("_First", 0);
        }

        //Renders the sky texture from skyTextureMaterial (previously rendered texture is used as its update texture)
        
        if (useSecondTexture)
        {
            Graphics.Blit(skyTexture, skyTexture2, skyTextureMaterial);
            useSecondTexture = false;
            RenderSettings.skybox.SetTexture("_Texture", skyTexture2);
        }
        else
        {
            Graphics.Blit(skyTexture2, skyTexture, skyTextureMaterial);
            useSecondTexture = true;
            RenderSettings.skybox.SetTexture("_Texture", skyTexture);
        }

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
        cloudMapMaterial.SetVector("_PositionDirection", new Vector4(position.x, position.y, -windDirection.X, -windDirection.Z));
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
            case 3:
                quality = QUALITY.Ultra;
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
        if (characterCamera == null)
        {
            characterCamera = Camera.main;
        }
        previousPosition = characterCamera.transform.position;
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
        shadowMaterial = (UnityEngine.Material)Resources.Load("Clouds/CloudShadow");
        RenderSettings.skybox = (UnityEngine.Material)Resources.Load("Clouds/Skybox-Image");

        /*
        Sets up basic variables for the sky rendering
        */
        updateTextureMaterial.SetColor("_SunTint", sunTint);
        updateTextureMaterial.SetFloat("_HdrExposure", HDRExposure);
        updateTextureMaterial.SetColor("_Clouds_Ambient_Bottom", ambientColorBottom);
        updateTextureMaterial.SetColor("_Clouds_Ambient_Top", ambientColorTop);
        updateTextureMaterial.SetFloat("_Density", 0.2f);
        RenderSettings.skybox.SetColor("_SunTint", sunTint);
        RenderSettings.skybox.SetFloat("_HdrExposure", HDRExposure);
        RenderSettings.skybox.SetColor("_Color", atmosphereTint);
        RenderSettings.skybox.SetColor("_GroundColor", groundColor);

        /*
        Big detail 3D texture - Layered Voronoi noise at different frequencies. Generated from a compute shader.
        The results are saved to noiseTexture_3D
        */
        noiseTexture_3D = new RenderTexture(64, 64, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        noiseTexture_3D.enableRandomWrite = true;
        noiseTexture_3D.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        noiseTexture_3D.volumeDepth = 64;
        noiseTexture_3D.Create();
        noiseGenerator = noiseShader.FindKernel("CSMain");
        noiseShader.SetTexture(noiseGenerator, "Result", noiseTexture_3D);
        float t = Time.time / 1000 + 10;
        noiseShader.SetFloat("Time", t);
        noiseShader.Dispatch(noiseGenerator, 64 / 8, 64 / 8, 64 / 8);
        updateTextureMaterial.SetTexture("_3dTexture", noiseTexture_3D);

        /*
        Small detail shader (used to add cloud details). The results are saved to detailNoiseTexture_3D
        */ 
        detailNoiseTexture_3D = new RenderTexture(32, 32, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        detailNoiseTexture_3D.enableRandomWrite = true;
        detailNoiseTexture_3D.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        detailNoiseTexture_3D.volumeDepth = 32;
        detailNoiseTexture_3D.Create();
        detailNoiseGenerator = noiseShaderDetail.FindKernel("CSMain");
        noiseShaderDetail.SetTexture(detailNoiseGenerator, "Result", detailNoiseTexture_3D);
        noiseShaderDetail.SetFloat("Time", t);
        noiseShaderDetail.Dispatch(detailNoiseGenerator, 32 / 8, 32 / 8, 32 / 8);
        updateTextureMaterial.SetTexture("_3dTexture_Distort", detailNoiseTexture_3D);

        /*
        Cloud Map - 2D texture tells us the cloud density at different parts of the sky
        */
        generatedCloudMap = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        generatedCloudMap.enableRandomWrite = true;
        generatedCloudMap.Create();
        if (generateCloudMap)
        {
            float totalProbability = cumulusAppearanceProbability + stratusAppearanceProbability + stratocumulusAppearanceProbability;
            if (totalProbability > 0.0)
            {
                cloudMapMaterial.SetVector("_CloudTypeProbs", new Vector4(cumulusAppearanceProbability / totalProbability, 
                    stratusAppearanceProbability / totalProbability, stratocumulusAppearanceProbability / totalProbability, 0.0f));
            }
            else {
                cloudMapMaterial.SetVector("_CloudTypeProbs", new Vector4(0.4f, 0.3f, 0.3f, 0.0f));
            }
            cloudMapGenerate(1);
            //Setting cloud map for the cloud update shader.
            updateTextureMaterial.SetTexture("_Cloud_Map", generatedCloudMap);
            shadowMaterial.SetTexture("_MainTex", generatedCloudMap);
        }
        else
        {
            updateTextureMaterial.SetTexture("_Cloud_Map", cloudMap);
            shadowMaterial.SetTexture("_MainTex", cloudMap);
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


        skyTexture2 = new RenderTexture(4 * (int)quality, 4 * (int)quality / 2, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        skyTexture2.enableRandomWrite = true;
        skyTexture2.Create();

        useSecondTexture = false;

        //Pass initial frame number 0 to updateTextureMaterial and skyTextureMaterial
        updateTextureMaterial.SetInt("_FrameNumber", 0);
        skyTextureMaterial.SetInt("_FrameNumber", 0);
        frameNumber = 0;


        /*
        Calls Update Shader 16 times. This updates all the pixels in the skyTexture.
        */
        for (int i = 0; i < 16; i++)
        {
            updateTexture(true);
        }

        foreach (MeshRenderer plane in GetComponentsInChildren<MeshRenderer>())
        {
            if (plane.name == "ShadowPlane")
            {
                shadowPlane = plane;
            }
        }
        shadowPlane.material = shadowMaterial;
    }

    void Update()
    {
        deltaTime += (Time.unscaledDeltaTime - deltaTime) * 0.1f;
        /*
         If settings change in the Unity inspector call the Start() function again and initialize all the necessary materials, shaders and textures there.
         */
        if (!Application.isPlaying)
        {
            noiseTexture_3D.Release();
            detailNoiseTexture_3D.Release();
            if (generateCloudMap)
            {
                generatedCloudMap.Release();
            }
            skyTextureUpdate.Release();
            skyTexture.Release();
            skyTexture2.Release();
            this.Start();
        }
        else
        {
            /*
            Generate update texture from the updateTextureMaterial
            */
            updateTexture(false);


            //Generates a cloud map for the next frame
            
            if (generateCloudMap)
            {
                cloudMapGenerate(0);
            }
            
            position = position + new Vector2(-windDirection.X, -windDirection.Z) * windSpeed * (Time.time - lastUpdateTime);
            lastUpdateTime = Time.time;
        }

    }
}
